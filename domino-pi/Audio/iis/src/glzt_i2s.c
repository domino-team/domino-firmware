/*
 * Copyright GL Technologies
 * Author: xinshouyong@gl-inet.com
 * */
#include <linux/module.h>
#include <linux/moduleparam.h>
#include <linux/init.h>
#include <linux/version.h>
#include <linux/kernel.h>	/* printk() */
#include <linux/slab.h>		/* kmalloc() */
#include <linux/fs.h>		/* everything... */
#include <linux/errno.h>	/* error codes */
#include <linux/types.h>	/* size_t */
#include <linux/proc_fs.h>
#include <linux/fcntl.h>	/* O_ACCMODE */
#include <linux/seq_file.h>
#include <linux/cdev.h>
#include <asm/uaccess.h>	/* copy_*_user */
#include <asm/io.h>
#include <linux/dma-mapping.h>
#include <linux/wait.h>
#include <linux/interrupt.h>
#include <linux/irqreturn.h>
#include <linux/math64.h>


#include "i2sio.h"
#include "ar7240.h"
#include "glzt_i2s.h"		/* local definitions */

#include <linux/device.h>
#include <linux/delay.h>
#include <linux/sched.h>
#include <linux/poll.h>
#include <linux/sound.h>
#include <linux/soundcard.h>
#include <linux/pm.h>
#include <linux/clk.h>
#include <linux/platform_device.h>
#include <asm/uaccess.h>
#include <asm/io.h>
#include <asm/dma.h>
#include <asm/dma-mapping.h>


#if (LINUX_VERSION_CODE >= KERNEL_VERSION(2,6,31))
#define ar7240_dma_cache_sync(b, c)              \
        do {                                            \
                dma_cache_sync(NULL, (void *)b,         \
                                c, DMA_FROM_DEVICE);    \
        } while (0)

#define ar7240_cache_inv(d, s)                   \
        do {                                            \
        } while (0)
#define AR7240_IRQF_DISABLED     IRQF_DISABLED
#else
#define ar7240_dma_cache_sync(b, c)              \
        do {                                            \
                dma_cache_wback((unsigned long)b, c);   \
        } while (0)
#define ar7240_cache_inv(d, s)                   \
        do {                                            \
                dma_cache_inv((unsigned long)d, s);     \
        } while (0)
#endif


/* Keep the below in sync with WLAN driver code
   parameters */
#define AOW_PER_DESC_INTERVAL 125      /* In usec */
#define DESC_FREE_WAIT_BUFFER 200      /* In usec */

#define TRUE    1
#define FALSE   !(TRUE)
//start oss
#define AUDIO_FMT_MASK (AFMT_S16_LE)
#define IIS_ABS(a) (a < 0 ? -a : a)

//end oss



//start oss


static int audio_dev_dsp;
static int audio_dev_mixer;



static int wm8978_volume;
static int mixer_igain=0x4; 
static int audio_mix_modcnt;

int ar7240_i2s_major = 14;
int ar7240_i2s_minor = 3;
int ar7240_i2s_num = 1;


module_param(ar7240_i2s_major, int, S_IRUGO);
module_param(ar7240_i2s_minor, int, S_IRUGO);

MODULE_AUTHOR("Jacob@Atheros");
MODULE_LICENSE("Dual BSD/GPL");


void ar7240_i2sound_i2slink_on(int master);
void ar7240_i2sound_request_dma_channel(int);
void ar7240_i2sound_dma_desc(unsigned long, int);
void ar7240_i2sound_dma_start(int);
void ar7240_i2sound_dma_pause(int);
void ar7240_i2sound_dma_resume(int);
void ar7240_i2s_clk(unsigned long, unsigned long);
int  ar7242_i2s_open(void); 
void ar7242_i2s_close(void);
irqreturn_t ar7240_i2s_intr(int irq, void *dev_id);


int ar7240_i2sound_dma_stopped(int);

/* 
 * XXX : This is the interface between i2s and wlan
 *       When adding info, here please make sure that
 *       it is reflected in the wlan side also
 */
typedef struct i2s_stats {
    unsigned int write_fail;
    unsigned int rx_underflow;
    unsigned int aow_sync_enabled;
    unsigned int sync_buf_full;
    unsigned int sync_buf_empty;
    unsigned int tasklet_count;
    unsigned int repeat_count;
} i2s_stats_t;   


typedef struct i2s_buf {
	uint8_t *bf_vaddr;     
	unsigned long bf_paddr;
} i2s_buf_t;


typedef struct i2s_dma_buf {
	ar7240_mbox_dma_desc *lastbuf;
	ar7240_mbox_dma_desc *db_desc;
	dma_addr_t db_desc_p;        
	i2s_buf_t db_buf[NUM_DESC];
	int tail;
} i2s_dma_buf_t;

typedef struct ar7240_i2s_softc {
	int ropened;
	int popened;
	i2s_dma_buf_t sc_pbuf;
	i2s_dma_buf_t sc_rbuf;
	char *sc_pmall_buf;
	char *sc_rmall_buf;
	int sc_irq;
	int ft_value;
	int ppause;
	int rpause;
	spinlock_t i2s_lock;   
	unsigned long i2s_lockflags;
} ar7240_i2s_softc_t;


i2s_stats_t stats;
ar7240_i2s_softc_t sc_buf_var;

int stereo_config_variable = 0;
static int audio_rate;
//static int audio_fmt;
static int audio_channels = 2 ;


/*
 * Functions and data structures relating to the Audio Sync feature
 *
 */

void glzt_set_gpio_to_l3(void)
{
	/*Set GPIO control wm8978 */
    
	ar7240_reg_rmw_set(RST_RESET,AR7240_RESET_I2S|AR7240_RESET_PCI_CORE);
    udelay(500);
	ar7240_reg_wr(AR7240_GPIO_OE,(IIS_CONTROL_CSB|IIS_CONTROL_SDIN|IIS_CONTROL_SCLK));	

}
void glzt_set_gpio_to_iis(void)
{
    /* Set GPIO I2S Enables */
    
    ar7240_reg_rmw_set(AR7240_GPIO_FUNCTIONS,
    	(AR7240_GPIO_FUNCTION_SPDIF_EN |
        AR7240_GPIO_FUNCTION_I2S_MCKEN | 
		AR7240_GPIO_FUNCTION_I2S0_EN|
		AR7240_GPIO_FUNCTION_I2S_GPIO_18_22_EN
		));
	ar7240_reg_rmw_set(AR7240_GPIO_FUNCTION_2, (1<<2)); //Enables the SPDIF output on GPIO2

}

void init_s3c2410_iis_bus(void)
{
	///unsigned long  a,b;
	
	ar7240_reg_wr(AR7240_STEREO_CONFIG,0);
	ar7240_reg_wr(AR7240_STEREO_CLK_DIV,0);
     
     

	stereo_config_variable = 0;
	stereo_config_variable = AR7240_STEREO_CONFIG_SPDIF_ENABLE;
	stereo_config_variable = stereo_config_variable | AR7240_STEREO_CONFIG_ENABLE;
	stereo_config_variable = stereo_config_variable | AR7240_STEREO_CONFIG_RESET;
	stereo_config_variable = stereo_config_variable | AR7240_STEREO_CONFIG_MIC_WORD_SIZE;
	stereo_config_variable = stereo_config_variable | AR7240_STEREO_CONFIG_MODE(0);
	stereo_config_variable = stereo_config_variable | AR7240_STEREO_CONFIG_DATA_WORD_SIZE(AR7240_STEREO_WS_16B);
	stereo_config_variable = stereo_config_variable | AR7240_STEREO_CONFIG_SAMPLE_CNT_CLEAR_TYPE;
	stereo_config_variable = stereo_config_variable | AR7240_STEREO_CONFIG_MASTER;
	stereo_config_variable = stereo_config_variable | AR7240_STEREO_CONFIG_PSEDGE(2);
	ar7240_reg_wr(AR7240_STEREO_CONFIG,0);
	ar7240_reg_wr(AR7240_STEREO_CONFIG,stereo_config_variable);


	
    ar7240_reg_wr(AR7240_STEREO_CLK_DIV,((0x11 << 16) + 0xb6b0));
    audio_rate = 44100;
    udelay(100);
    ar7240_reg_rmw_clear(AR7240_STEREO_CONFIG, AR7240_STEREO_CONFIG_RESET);
	
}

void ar7240_gpio_setpin(unsigned int pin, unsigned int to)
{
	unsigned long flags;
	unsigned long dat;
	if(to)
	{
		local_irq_save(flags);
		
		//ar7240_reg_rmw_clear(AR7240_GPIO_OE,(AR7240_LED_3|AR7240_LED_4|AR7240_LED_5));
		ar7240_reg_rmw_clear(AR7240_GPIO_OE,(IIS_CONTROL_CSB|IIS_CONTROL_SDIN|IIS_CONTROL_SCLK));
		dat = ar7240_reg_rd(AR7240_GPIO_IN);

		dat |= pin;   
		//ar7240_reg_wr(AR7240_GPIO_OE,(AR7240_LED_3|AR7240_LED_4|AR7240_LED_5));
		ar7240_reg_wr(AR7240_GPIO_OE,(IIS_CONTROL_CSB|IIS_CONTROL_SDIN|IIS_CONTROL_SCLK));		 
		ar7240_reg_wr(AR7240_GPIO_OUT,dat); //Ð´

		local_irq_restore(flags);
	}
	else
	{
		local_irq_save(flags);
		
		//ar7240_reg_rmw_clear(AR7240_GPIO_OE,(AR7240_LED_3|AR7240_LED_4|AR7240_LED_5));
		ar7240_reg_rmw_clear(AR7240_GPIO_OE,(IIS_CONTROL_CSB|IIS_CONTROL_SDIN|IIS_CONTROL_SCLK));
		dat = ar7240_reg_rd(AR7240_GPIO_IN);

		dat &= ~(pin); 

		//ar7240_reg_wr(AR7240_GPIO_OE,(AR7240_LED_3|AR7240_LED_4|AR7240_LED_5));		
		ar7240_reg_wr(AR7240_GPIO_OE,(IIS_CONTROL_CSB|IIS_CONTROL_SDIN|IIS_CONTROL_SCLK));
		ar7240_reg_wr(AR7240_GPIO_OUT,dat); 

		local_irq_restore(flags);
	}
}




static void wm8978_write_reg(unsigned char reg, unsigned int data)
{
	int i;
	unsigned long flags;
	unsigned short val = (reg << 9) | (data & 0x1ff);
	
	ar7240_gpio_setpin(IIS_CONTROL_CSB,1);
	ar7240_gpio_setpin(IIS_CONTROL_SDIN,1);
	ar7240_gpio_setpin(IIS_CONTROL_SCLK,1);
	
	local_irq_save(flags);
	
	for (i = 0; i < 16; i++){
		if (val & (1<<15))
		{
			ar7240_gpio_setpin(IIS_CONTROL_SCLK,0);
			ar7240_gpio_setpin(IIS_CONTROL_SDIN,1);
			udelay(1);
			ar7240_gpio_setpin(IIS_CONTROL_SCLK,1); 		
		}
		else
		{
			ar7240_gpio_setpin(IIS_CONTROL_SCLK,0);
			ar7240_gpio_setpin(IIS_CONTROL_SDIN,0);
			udelay(1);
			ar7240_gpio_setpin(IIS_CONTROL_SCLK,1); 		
		}
	
		val = val << 1;
	}
	
	ar7240_gpio_setpin(IIS_CONTROL_CSB,0);	
	udelay(1);
	ar7240_gpio_setpin(IIS_CONTROL_CSB,1);
	ar7240_gpio_setpin(IIS_CONTROL_SDIN,1);
	ar7240_gpio_setpin(IIS_CONTROL_SCLK,1);
	local_irq_restore(flags);	
}



static void init_wm8978(void)
{
	/* software reset */
	wm8978_write_reg(0, 0);

	wm8978_write_reg(0x3, 0x6f);
	
	wm8978_write_reg(0x1, 0x1f);//biasen,BUFIOEN.VMIDSEL=11b  
	wm8978_write_reg(0x2, 0x185);//ROUT1EN LOUT1EN, inpu PGA enable ,ADC enable

	wm8978_write_reg(0x6, 0x0);//SYSCLK=MCLK  
	wm8978_write_reg(0x4, 0x10);//16bit 		
	wm8978_write_reg(0x2B,0x10);//BTL OUTPUT  
	wm8978_write_reg(0x9, 0x50);//Jack detect enable  
	wm8978_write_reg(0xD, 0x21);//Jack detect  
	wm8978_write_reg(0x7, 0x01);//Jack detect 

}



static long smdk2410_mixer_ioctl(struct file *file,
				unsigned int cmd, unsigned long arg)
{
	int ret;
	long val = 0;
	//mixer_info info;
	//_old_mixer_info info;

	switch (cmd) {
		case SOUND_MIXER_INFO:
		{
			printk("SOUND_MIXER_INFO\n");
			//mixer_info info;
			/*
			strncpy(info.id, "WM8978", sizeof(info.id));
			strncpy(info.name,"Wolfson WM8978", sizeof(info.name));
			info.modify_counter = audio_mix_modcnt;
			return copy_to_user((void *)arg, &info, sizeof(info));
			*/
			break;
		}

		case SOUND_OLD_MIXER_INFO:
		{
			printk("SOUND_OLD_MIXER_INFO\n");
			//_old_mixer_info info;
			/*
			strncpy(info.id, "WM8978", sizeof(info.id));
			strncpy(info.name,"Wolfson WM8978", sizeof(info.name));
			return copy_to_user((void *)arg, &info, sizeof(info));
			*/
			break;
		}

		case SOUND_MIXER_READ_STEREODEVS:
			printk("SOUND_MIXER_READ_STEREODEVS\n");
			return put_user(0, (long *) arg);

		case SOUND_MIXER_READ_CAPS:
			printk("SOUND_MIXER_READ_CAPS\n");
			val = SOUND_CAP_EXCL_INPUT;
			return put_user(val, (long *) arg);

		case SOUND_MIXER_WRITE_VOLUME:
			printk("SOUND_MIXER_WRITE_VOLUME\n");
			ret = get_user(val, (long *) arg);
			if (ret)
				return ret;
			//uda1341_volume = 63 - (((val & 0xff) + 1) * 63) / 100;
			//uda1341_l3_address(UDA1341_REG_DATA0);
			//uda1341_l3_data(uda1341_volume);
			wm8978_volume = ((val & 0xff)*32)/100; 
			wm8978_write_reg(52,((1<<8)|wm8978_volume));
			wm8978_write_reg(53,((1<<8)|wm8978_volume));
			break;

		case SOUND_MIXER_READ_VOLUME:
			printk("SOUND_MIXER_READ_VOLUME\n");
			//val = ((63 - uda1341_volume) * 100) / 63;
			//val |= val << 8;
			val = (wm8978_volume * 100)/63;
			return put_user(val, (long *) arg);

		case SOUND_MIXER_READ_IGAIN:
			printk("SOUND_MIXER_READ_IGAIN\n");
			val = ((31- mixer_igain) * 100) / 31;
			return put_user(val, (int *) arg);

		case SOUND_MIXER_WRITE_IGAIN:
			printk("SOUND_MIXER_WRITE_IGAIN\n");
			ret = get_user(val, (int *) arg);
			if (ret)
				return ret;
			mixer_igain = 31 - (val * 31 / 100);
			/* use mixer gain channel 1*/
			//uda1341_l3_address(UDA1341_REG_DATA0);
			//uda1341_l3_data(EXTADDR(EXT0));
			//uda1341_l3_data(EXTDATA(EXT0_CH1_GAIN(mixer_igain)));
			break;

		default:
			printk("mixer ioctl %u unknown\n", cmd);
			return -ENOSYS;
	}

	audio_mix_modcnt++;
	return 0;
}

static int smdk2410_mixer_open(struct inode *inode, struct file *file)
{
	return 0;
}
static int smdk2410_mixer_release(struct inode *inode, struct file *file)
{
	return 0;
}



static struct file_operations smdk2410_mixer_fops = {
	.unlocked_ioctl = smdk2410_mixer_ioctl,
	.open = smdk2410_mixer_open,
	.release = smdk2410_mixer_release
};




int ar7240_i2s_init(struct file *filp)
{
	ar7240_i2s_softc_t *sc = &sc_buf_var;
	i2s_dma_buf_t *dmabuf;
	i2s_buf_t *scbuf;
	uint8_t *bufp = NULL;
	int j, byte_cnt, tail = 0, mode = 1;
	ar7240_mbox_dma_desc *desc;
	unsigned long desc_p;
	
    if (!filp) {
        mode = FMODE_WRITE;
    } else {
        mode = filp->f_mode;
    }

	if (mode & FMODE_READ) {
		dmabuf = &sc->sc_rbuf;
		sc->ropened = 1;
		sc->rpause = 0;
	} else {
		dmabuf = &sc->sc_pbuf;
		sc->popened = 1;
		sc->ppause = 0;
	}

	dmabuf->db_desc = (ar7240_mbox_dma_desc *)dma_alloc_coherent(NULL,
				       NUM_DESC *sizeof(ar7240_mbox_dma_desc),
				       &dmabuf->db_desc_p, GFP_DMA);

	if (dmabuf->db_desc == NULL) {
		printk(KERN_CRIT "DMA desc alloc failed for %d\n",mode);
			return ENOMEM;
	}
	

	for (j = 0; j < NUM_DESC; j++) {
		dmabuf->db_desc[j].OWN = 0;
	}


	/* Allocate data buffers */
	scbuf = dmabuf->db_buf;

	if (!(bufp = kmalloc(NUM_DESC * I2S_BUF_SIZE, GFP_KERNEL))) {
			printk(KERN_CRIT"Buffer allocation failed for \n");
			goto fail3;
	}

	if (mode & FMODE_READ)
		sc->sc_rmall_buf = bufp;
	else
		sc->sc_pmall_buf = bufp;
	

	for (j = 0; j < NUM_DESC; j++) {
		scbuf[j].bf_vaddr = &bufp[j * I2S_BUF_SIZE];
		scbuf[j].bf_paddr =dma_map_single(NULL, scbuf[j].bf_vaddr,I2S_BUF_SIZE,DMA_BIDIRECTIONAL);
	}
	dmabuf->tail = 0;

	// Initialize desc
	desc = dmabuf->db_desc;
	desc_p = (unsigned long) dmabuf->db_desc_p;
	byte_cnt = NUM_DESC * I2S_BUF_SIZE;
	tail = dmabuf->tail;

	while (byte_cnt && (tail < NUM_DESC)) {
		desc[tail].rsvd1 = 0;
		desc[tail].size = I2S_BUF_SIZE;
		
		if (byte_cnt > I2S_BUF_SIZE) {
			desc[tail].length = I2S_BUF_SIZE;
			byte_cnt -= I2S_BUF_SIZE;
			desc[tail].EOM = 0;
		} else {
			desc[tail].length = byte_cnt;
			byte_cnt = 0;
			desc[tail].EOM = 0;
		}
		
		desc[tail].rsvd2 = 0;
		desc[tail].rsvd3 = 0;
		desc[tail].BufPtr =(unsigned int) scbuf[tail].bf_paddr;
		desc[tail].NextPtr =(desc_p +((tail +1) *(sizeof(ar7240_mbox_dma_desc))));
		if (mode & FMODE_READ) {
			desc[tail].OWN = 1;
		} else {
			desc[tail].OWN = 0;
		}
		tail++;
	}
	tail--;
	desc[tail].NextPtr = desc_p;
	dmabuf->tail = 0;
	return 0;

fail3:
	if (mode & FMODE_READ)
		dmabuf = &sc->sc_rbuf;
	else
		dmabuf = &sc->sc_pbuf;
	
	dma_free_coherent(NULL,NUM_DESC * sizeof(ar7240_mbox_dma_desc),dmabuf->db_desc, dmabuf->db_desc_p);
	

	if (mode & FMODE_READ) {
		if (sc->sc_rmall_buf)
			kfree(sc->sc_rmall_buf);
	} 
	else{
		if (sc->sc_pmall_buf)
			kfree(sc->sc_pmall_buf);
	}

	return -ENOMEM;

}


//´ò¿ªÎÄ¼þ
int ar7240_i2s_open(struct inode *inode, struct file *filp)
{

	ar7240_i2s_softc_t *sc = &sc_buf_var;
	int opened = 0, mode = MASTER;


	if ((filp->f_mode & FMODE_READ) && (sc->ropened)) {
        printk("%s, %d I2S mic busy\n", __func__, __LINE__);
		return -EBUSY;
	}
	if ((filp->f_mode & FMODE_WRITE) && (sc->popened)) {
        printk("%s, %d I2S speaker busy\n", __func__, __LINE__);
		return -EBUSY;
	}

	opened = (sc->ropened | sc->popened);

	/* Reset MBOX FIFO's */
	if (!opened) {
		//2bit/0bit:Writing a 1 causes a RX/TX FIFO reset,		
		//The register is automatically reset to 0, and will always return 0 on a read		
		//
		ar7240_reg_wr(MBOX_FIFO_RESET, 0xff); // virian
		udelay(500);
	}

	/* Allocate and initialize descriptors */
	if (ar7240_i2s_init(filp) == ENOMEM)
		return -ENOMEM;

	if (!opened) {
	    ar7240_i2sound_request_dma_channel(mode);
    }

	return (0);

}


ssize_t ar7240_i2s_read(struct file * filp, char __user * buf,size_t count, loff_t * f_pos)//gl-inet
{
#define prev_tail(t) ({ (t == 0) ? (NUM_DESC - 1) : (t - 1); })
#define next_tail(t) ({ (t == (NUM_DESC - 1)) ? 0 : (t + 1); })

	uint8_t *data;
	//ssize_t retval;
	unsigned long retval;
	struct ar7240_i2s_softc *sc = &sc_buf_var;
	i2s_dma_buf_t *dmabuf = &sc->sc_rbuf;
	i2s_buf_t *scbuf;
	ar7240_mbox_dma_desc *desc;
	unsigned int byte_cnt, mode = 1, offset = 0, tail = dmabuf->tail;
	unsigned long desc_p;
	int need_start = 0;

	byte_cnt = count;

	if (sc->ropened < 2) {
		ar7240_reg_rmw_set(MBOX_INT_ENABLE, MBOX0_TX_DMA_COMPLETE);
		need_start = 1;
	}

	sc->ropened = 2;

	scbuf = dmabuf->db_buf;
	desc = dmabuf->db_desc;
	desc_p = (unsigned long) dmabuf->db_desc_p;
	data = scbuf[0].bf_vaddr;

	desc_p += tail * sizeof(ar7240_mbox_dma_desc);

	while (byte_cnt && !desc[tail].OWN) {
		if (byte_cnt >= I2S_BUF_SIZE) {
			desc[tail].length = I2S_BUF_SIZE;
			byte_cnt -= I2S_BUF_SIZE;
		} else {
			desc[tail].length = byte_cnt;
			byte_cnt = 0;
		}
		//ar7240_dma_cache_sync(scbuf[tail].bf_vaddr, desc[tail].length);//gl-inet

		dma_cache_sync(NULL, scbuf[tail].bf_vaddr, desc[tail].length, DMA_FROM_DEVICE);//gl-inet		
		desc[tail].rsvd2 = 0;//gl-inet
		
		retval = copy_to_user((buf + offset), (scbuf[tail].bf_vaddr), I2S_BUF_SIZE);

		if (retval)
			return retval;
		desc[tail].BufPtr = (unsigned int) scbuf[tail].bf_paddr;
		desc[tail].OWN = 1;

		tail = next_tail(tail);
		offset += I2S_BUF_SIZE;
	}

	dmabuf->tail = tail;

	if (need_start) {
		ar7240_i2sound_dma_desc((unsigned long) desc_p, mode);
        if (filp) {
		    ar7240_i2sound_dma_start(mode);
        }
	} else if (!sc->rpause) {
		ar7240_i2sound_dma_resume(mode);
	}

	return offset;
}


ssize_t ar7240_i2s_write(struct file * filp, const char __user * buf,
			 size_t count, loff_t * f_pos, int resume)
{
#define prev_tail(t) ({ (t == 0) ? (NUM_DESC - 1) : (t - 1); })
#define next_tail(t) ({ (t == (NUM_DESC - 1)) ? 0 : (t + 1); })

//	uint8_t *data;
	ssize_t retval;
	
	int byte_cnt, offset, need_start = 0;
	int mode = 0;
	struct ar7240_i2s_softc *sc = &sc_buf_var;
	i2s_dma_buf_t *dmabuf = &sc->sc_pbuf;
	i2s_buf_t *scbuf;
	ar7240_mbox_dma_desc *desc;
	int tail = dmabuf->tail;
	unsigned long desc_p;
    int data_len = 0;


	I2S_LOCK(sc);

	byte_cnt = count;
	//printk("count:%d\n",count);
	//printk("byte_cnt:%d\n",byte_cnt);

	if (sc->popened < 2) {
        ar7240_reg_rmw_set(MBOX_INT_ENABLE, MBOX0_RX_DMA_COMPLETE | RX_UNDERFLOW);
		need_start = 1;
	}

	sc->popened = 2;

	scbuf = dmabuf->db_buf;
	desc = dmabuf->db_desc;
	desc_p = (unsigned long) dmabuf->db_desc_p;
	offset = 0;
	//data = scbuf[0].bf_vaddr;

	desc_p += tail * sizeof(ar7240_mbox_dma_desc);

	while (byte_cnt && !desc[tail].OWN) {
        if (byte_cnt >= I2S_BUF_SIZE) {
			desc[tail].length = I2S_BUF_SIZE;
			byte_cnt -= I2S_BUF_SIZE;
            data_len = I2S_BUF_SIZE;
		} else {
			desc[tail].length = byte_cnt;
            data_len = byte_cnt;
			byte_cnt = 0;
		}

        if(!filp)
        {
            memcpy(scbuf[tail].bf_vaddr, buf + offset, data_len);
        }
        else
        {
            retval = copy_from_user(scbuf[tail].bf_vaddr, buf + offset, data_len);
            if (retval)
                return retval;
        }
		ar7240_cache_inv(scbuf[tail].bf_vaddr, desc[tail].length);

        dma_cache_sync(NULL, scbuf[tail].bf_vaddr, desc[tail].length, DMA_TO_DEVICE);
		
		desc[tail].BufPtr = (unsigned int) scbuf[tail].bf_paddr;
		desc[tail].OWN = 1;
		tail = next_tail(tail);
		offset += data_len;
	}

	dmabuf->tail = tail;

	if (need_start) {
		ar7240_i2sound_dma_desc((unsigned long) desc_p, mode);
		ar7240_i2sound_dma_start(mode);
	}
	else if (!sc->ppause) {
		ar7240_i2sound_dma_resume(mode);
	}

//    if (resume)
//        ar7240_i2sound_dma_resume(mode);

	I2S_UNLOCK(sc);
	//all_data+=(count - byte_cnt);

	//printk("all_data:%ld\n",all_data);
	//glzt_msleep(10);

	return count - byte_cnt;
}




ssize_t ar9100_i2s_write(struct file * filp, const char __user * buf,size_t count, loff_t * f_pos)
{
    int tmpcount, ret = 0;
    int cnt = 0;
//    char *data;
	

eagain:
    tmpcount = count;
   // data = buf;
    ret = 0;


    do {
        ret = ar7240_i2s_write(filp, buf, tmpcount, f_pos, 1);
        cnt++;
        if (ret == EAGAIN) {
            printk("%s:%d %d\n", __func__, __LINE__, ret);
            goto eagain;
        }

        tmpcount = tmpcount - ret;
        buf += ret;
    } while(tmpcount > 0);

    return count;
}




int ar7240_i2s_close(struct inode *inode, struct file *filp)
{
	int j, own, mode;
	ar7240_i2s_softc_t *sc = &sc_buf_var;
	i2s_dma_buf_t *dmabuf;
	ar7240_mbox_dma_desc *desc;
    int status = TRUE;
    int own_count = 0;

    if (!filp) {
        mode  = 0;
    } else {
        mode = filp->f_mode;
    }

	if (mode & FMODE_READ) {
		dmabuf = &sc->sc_rbuf;
		own = sc->rpause;
	} else {
		dmabuf = &sc->sc_pbuf;
		own = sc->ppause;
	}

	desc = dmabuf->db_desc;
	if (own) {
		for (j = 0; j < NUM_DESC; j++) {
			desc[j].OWN = 0;
		}
		ar7240_i2sound_dma_resume(mode);
    } else {
        for (j = 0; j < NUM_DESC; j++) {
            if (desc[j].OWN) {
                own_count++;
            }
        }
        
        /* 
         * The schedule_timeout_interruptible is commented
         * as this function is called from other process
         * context, i.e. that of wlan device driver context
         * schedule_timeout_interruptible(HZ);
         */
        if (own_count > 0) { 
            udelay((own_count * AOW_PER_DESC_INTERVAL) + DESC_FREE_WAIT_BUFFER);
            
            for (j = 0; j < NUM_DESC; j++) {
                /* break if the descriptor is still not free*/
                if (desc[j].OWN) {
                    status = FALSE;
                    printk("I2S : Fatal error\n");
                    break;
                }
            }
        }
    }
	for (j = 0; j < NUM_DESC; j++) {
		dma_unmap_single(NULL, dmabuf->db_buf[j].bf_paddr,
				 I2S_BUF_SIZE, DMA_BIDIRECTIONAL);
	}

	if (mode & FMODE_READ)
		kfree(sc->sc_rmall_buf);
	else
		kfree(sc->sc_pmall_buf);
	dma_free_coherent(NULL,
			  NUM_DESC * sizeof(ar7240_mbox_dma_desc),
			  dmabuf->db_desc, dmabuf->db_desc_p);

	if (mode & FMODE_READ) {
		sc->ropened = 0;
		sc->rpause = 0;
	} else {
		sc->popened = 0;
		sc->ppause = 0;
	}

	return (status);
}

int ar7240_i2s_release(struct inode *inode, struct file *filp)
{
	printk(KERN_CRIT "release\n");
	return 0;
}


static long ar7240_i2s_ioctl(struct file *filp,unsigned int cmd, unsigned long arg)
{ 

	
	int data;
	long val;
	struct ar7240_i2s_softc *sc = &sc_buf_var;
	i2s_dma_buf_t *dmabuf;

    if (filp->f_mode & FMODE_READ) {
        dmabuf = &sc->sc_rbuf;
    } else {
        dmabuf = &sc->sc_pbuf;
	}


	switch (cmd) {
		case I2S_FREQ:		/* Frequency settings */
			data = arg;
			printk("set athplay I2S_FREQ:data=%d\n",data);
			switch (data) {
				case 44100:						   
					ar7240_reg_wr(AR7240_STEREO_CLK_DIV,((0x11 << 16) + 0xb6b0));//gl-inet 44100kHz		
					break;
				case 48000:
					ar7240_reg_wr(AR7240_STEREO_CLK_DIV,((0x10 << 16) + 0x4600));//gl-inet 48000kHz
					break;
				default:
					printk(KERN_CRIT "Freq %d not supported \n",data);
					return -ENOTSUPP;	
			}
			break;

		case I2S_DSIZE:
			data = arg;
			printk("set athplay I2S_DSIZE:data=%d\n",data);
			switch (data) {
				case 8:
					stereo_config_variable = 0;
					stereo_config_variable = AR7240_STEREO_CONFIG_SPDIF_ENABLE;
					stereo_config_variable = stereo_config_variable | AR7240_STEREO_CONFIG_ENABLE;
					stereo_config_variable = stereo_config_variable | AR7240_STEREO_CONFIG_RESET;
					stereo_config_variable = stereo_config_variable | AR7240_STEREO_CONFIG_MIC_WORD_SIZE;
					stereo_config_variable = stereo_config_variable | AR7240_STEREO_CONFIG_MODE(0);
					stereo_config_variable = stereo_config_variable | AR7240_STEREO_CONFIG_DATA_WORD_SIZE(AR7240_STEREO_WS_16B);
					stereo_config_variable = stereo_config_variable | AR7240_STEREO_CONFIG_SAMPLE_CNT_CLEAR_TYPE;
					stereo_config_variable = stereo_config_variable | AR7240_STEREO_CONFIG_MASTER;
					stereo_config_variable = stereo_config_variable | AR7240_STEREO_CONFIG_PSEDGE(2);
					break;
					
				case 16:
					stereo_config_variable = 0;
					stereo_config_variable = AR7240_STEREO_CONFIG_SPDIF_ENABLE;
					stereo_config_variable = stereo_config_variable | AR7240_STEREO_CONFIG_ENABLE;
					stereo_config_variable = stereo_config_variable | AR7240_STEREO_CONFIG_RESET;
					stereo_config_variable = stereo_config_variable | AR7240_STEREO_CONFIG_PCM_SWAP;
					stereo_config_variable = stereo_config_variable | AR7240_STEREO_CONFIG_MIC_WORD_SIZE;
					stereo_config_variable = stereo_config_variable | AR7240_STEREO_CONFIG_MODE(0);
					stereo_config_variable = stereo_config_variable | AR7240_STEREO_CONFIG_DATA_WORD_SIZE(AR7240_STEREO_WS_16B);
					stereo_config_variable = stereo_config_variable | AR7240_STEREO_CONFIG_I2S_32B_WORD;
					stereo_config_variable = stereo_config_variable | AR7240_STEREO_CONFIG_SAMPLE_CNT_CLEAR_TYPE;
					stereo_config_variable = stereo_config_variable | AR7240_STEREO_CONFIG_MASTER;
					stereo_config_variable = stereo_config_variable | AR7240_STEREO_CONFIG_PSEDGE(2);
					break;
					
				case 24:
					printk("set athplay I2S_DSIZE:24 don't make\n");
					break;
				case 32:
					printk("set athplay I2S_DSIZE:32 don't make\n");
					break;
					
			}
			break;
		
		case SNDCTL_DSP_SETFMT:
			//get_user(val, (long *) arg);
			//printk("SNDCTL_DSP_SETFMT,%ld\n",val);
			//printk("1\n");
			/*
			if (val & AUDIO_FMT_MASK) {
				audio_fmt = val;
				break;
			} else
				return -EINVAL;
			*/
			break;
		case SNDCTL_DSP_CHANNELS:
		case SNDCTL_DSP_STEREO:
			get_user(data, (long *) arg);
			audio_channels = data;
			//printk("STEREO%d\n",audio_channels);
	    	//For MONO 
			if (data) {
				stereo_config_variable = 0;
				stereo_config_variable = AR7240_STEREO_CONFIG_SPDIF_ENABLE;
				stereo_config_variable = stereo_config_variable | AR7240_STEREO_CONFIG_ENABLE;
				stereo_config_variable = stereo_config_variable | AR7240_STEREO_CONFIG_RESET;
				stereo_config_variable = stereo_config_variable | AR7240_STEREO_CONFIG_MIC_WORD_SIZE;
				stereo_config_variable = stereo_config_variable | AR7240_STEREO_CONFIG_MODE(0);
				stereo_config_variable = stereo_config_variable | AR7240_STEREO_CONFIG_DATA_WORD_SIZE(AR7240_STEREO_WS_16B);
				stereo_config_variable = stereo_config_variable | AR7240_STEREO_CONFIG_SAMPLE_CNT_CLEAR_TYPE;
				stereo_config_variable = stereo_config_variable | AR7240_STEREO_CONFIG_MASTER;
				stereo_config_variable = stereo_config_variable | AR7240_STEREO_CONFIG_PSEDGE(2);    
        	} else {
                stereo_config_variable = 0;
				stereo_config_variable = AR7240_STEREO_CONFIG_SPDIF_ENABLE;
				stereo_config_variable = stereo_config_variable | AR7240_STEREO_CONFIG_ENABLE;
				stereo_config_variable = stereo_config_variable | AR7240_STEREO_CONFIG_RESET;
				stereo_config_variable = stereo_config_variable | AR7240_STEREO_CONFIG_MIC_WORD_SIZE;
				stereo_config_variable = stereo_config_variable | AR7240_STEREO_CONFIG_MODE(1);
				stereo_config_variable = stereo_config_variable | AR7240_STEREO_CONFIG_DATA_WORD_SIZE(AR7240_STEREO_WS_16B);
				stereo_config_variable = stereo_config_variable | AR7240_STEREO_CONFIG_SAMPLE_CNT_CLEAR_TYPE;
				stereo_config_variable = stereo_config_variable | AR7240_STEREO_CONFIG_MASTER;
				stereo_config_variable = stereo_config_variable | AR7240_STEREO_CONFIG_PSEDGE(2);
     
        	}

			break;
		case SOUND_PCM_READ_CHANNELS:
			//printk("send CHANNELS\n");
			put_user(audio_channels, (long *) arg);
			break;

		case SNDCTL_DSP_SPEED:
			get_user(val, (long *) arg);
			audio_rate = val;
			//printk("SNDCTL_DSP_SPEED:%ld\n",val);
			switch (audio_rate) {
				case 8000: 			
				ar7240_reg_wr(AR7240_STEREO_CLK_DIV,((0x61 << 16) + 0xa100));//gl-inet 8000Hz
					audio_rate = 8000;				
					break;

				case 11025: 				   
					ar7240_reg_wr(AR7240_STEREO_CLK_DIV,((0x46 << 16) + 0xdc00));//gl-inet 11025Hz
					audio_rate = 11025;		
					break;

				case 12000: 				   
					ar7240_reg_wr(AR7240_STEREO_CLK_DIV,((0x41 << 16) + 0x1b00));//gl-inet 12000Hz
					audio_rate = 12000;				
					break;

				case 16000: 				   
					ar7240_reg_wr(AR7240_STEREO_CLK_DIV,((0x30 << 16) + 0xd400));//gl-inet 16000Hz				
					audio_rate = 16000;				
					break;

				case 22050: 				   
					ar7240_reg_wr(AR7240_STEREO_CLK_DIV,((0x23 << 16) + 0x6e00));//gl-inet 22050Hz									
					audio_rate = 22050;
					break;

				case 24000:					   
					ar7240_reg_wr(AR7240_STEREO_CLK_DIV,((0x20 << 16) + 0x8d00));//gl-inet 24000Hz											
					audio_rate = 24000;
					break;

				case 32000:
					ar7240_reg_wr(AR7240_STEREO_CLK_DIV,((0x18 << 16) + 0x6200));//gl-inet 32000Hz	
					audio_rate = 32000;
					break;		
				case 44100:					   
					ar7240_reg_wr(AR7240_STEREO_CLK_DIV,((0x11 << 16) + 0xb6b0));//gl-inet 44100kHz
					audio_rate = 44100;
					break;
				case 48000:
					ar7240_reg_wr(AR7240_STEREO_CLK_DIV,((0x10 << 16) + 0x4600));//gl-inet 48000kHz
					audio_rate = 48000;
					break;
				default:
					printk(KERN_CRIT "Freq %d not supported \n",data);
					return -ENOTSUPP;
			}
			if (val < 0)
				return -EINVAL;
			put_user(val, (long *) arg);
			break;

		case SOUND_PCM_READ_RATE:
			printk("send RATE: audio_rate\n");
			put_user(audio_rate, (long *) arg);
			break;
			

		case SNDCTL_DSP_RESET:
			//printk("2\n");
			break;
						
			





		case SNDCTL_DSP_GETFMTS:
			printk("SNDCTL_DSP_GETFMTS:no use\n");
			//printk("!!!SNDCTL_DSP_GETFMTS,send AUDIO_FMT_MASK = %d\n",AUDIO_FMT_MASK);
			//put_user(AUDIO_FMT_MASK, (long *) arg);
			break;

		case SNDCTL_DSP_GETBLKSIZE:
			printk("SNDCTL_DSP_GETBLKSIZE:no use\n");

			break;

		case SNDCTL_DSP_SETFRAGMENT:
			printk("SNDCTL_DSP_SETFRAGMENT:no use\n");
			
			break;

		case SNDCTL_DSP_SYNC:
			printk("SNDCTL_DSP_SYNC:no use\n");
			//return audio_sync(file);
			break;
		case SNDCTL_DSP_GETOSPACE:
			{
			printk("SNDCTL_DSP_GETOSPACE:no use\n");
			/*
			audio_stream_t *s = &output_stream;
			audio_buf_info *inf = (audio_buf_info *) arg;
			int err = access_ok(VERIFY_WRITE, inf, sizeof(*inf));
			int i;
			int frags = 0, bytes = 0;

			if (err)
				return err;
			for (i = 0; i < s->nbfrags; i++) {
				if (atomic_read(&s->buffers[i].sem.count) > 0) {
					if (s->buffers[i].size == 0) frags++;
					bytes += s->fragsize - s->buffers[i].size;
				}
			}
			put_user(frags, &inf->fragments);
			put_user(s->nbfrags, &inf->fragstotal);
			put_user(s->fragsize, &inf->fragsize);
			put_user(bytes, &inf->bytes);
			*/
			break;
			}

		case SNDCTL_DSP_GETISPACE://·µ»Ø¿Õ¼äÊ¹ÓÃÇé¿ö
			{
			printk("SNDCTL_DSP_GETISPACE:no use\n");
			/*
			audio_stream_t *s = &input_stream;
			audio_buf_info *inf = (audio_buf_info *) arg;
			int err = access_ok(VERIFY_WRITE, inf, sizeof(*inf));
			int i;
			int frags = 0, bytes = 0;

			if (!(file->f_mode & FMODE_READ))
				return -EINVAL;

			if (err)
				return err;
			for(i = 0; i < s->nbfrags; i++){
				if (atomic_read(&s->buffers[i].sem.count) > 0)
				{
					if (s->buffers[i].size == s->fragsize)
						frags++;
					bytes += s->buffers[i].size;
				}
			}
			put_user(frags, &inf->fragments);
			put_user(s->nbfrags, &inf->fragstotal);
			put_user(s->fragsize, &inf->fragsize);
			put_user(bytes, &inf->bytes);
			*/
			break;
			}
		
		case SNDCTL_DSP_NONBLOCK:
			printk("SNDCTL_DSP_NONBLOCK:set O_NONBLOCK\n");
			filp->f_flags |= O_NONBLOCK;
			break;

		
		case SNDCTL_DSP_POST:printk("SNDCTL_DSP_POST\n");
		case SNDCTL_DSP_SUBDIVIDE:printk("SNDCTL_DSP_SUBDIVIDE\n");
		case SNDCTL_DSP_GETCAPS:printk("SNDCTL_DSP_GETCAPS\n");
		case SNDCTL_DSP_GETTRIGGER:printk("SNDCTL_DSP_GETTRIGGER\n");
		case SNDCTL_DSP_SETTRIGGER:printk("SNDCTL_DSP_SETTRIGGER\n");
		case SNDCTL_DSP_GETIPTR:printk("SNDCTL_DSP_GETIPTR\n");
		case SNDCTL_DSP_GETOPTR:printk("SNDCTL_DSP_GETOPTR\n");
		case SNDCTL_DSP_MAPINBUF:printk("SNDCTL_DSP_MAPINBUF\n");
		case SNDCTL_DSP_MAPOUTBUF:printk("SNDCTL_DSP_MAPOUTBUF\n");
		case SNDCTL_DSP_SETSYNCRO:printk("SNDCTL_DSP_SETSYNCRO\n");
		case SNDCTL_DSP_SETDUPLEX:printk("SNDCTL_DSP_SETDUPLEX\n");
			printk("no use,rerurn ENOSYS\n");
			return -ENOSYS;
		default:
			return smdk2410_mixer_ioctl(filp, cmd, arg);
	}

	ar7240_reg_wr(AR7240_STEREO_CONFIG,0);
	ar7240_reg_wr(AR7240_STEREO_CONFIG, (stereo_config_variable | AR7240_STEREO_CONFIG_RESET));
	udelay(100);
	ar7240_reg_rmw_clear(AR7240_STEREO_CONFIG,AR7240_STEREO_CONFIG_RESET);
	ar7240_reg_wr(AR7240_STEREO_CONFIG, stereo_config_variable);


	
	wm8978_volume = ((100 & 0xff)*32)/100; 
	wm8978_write_reg(52,((1<<8)|wm8978_volume));
	wm8978_write_reg(53,((1<<8)|wm8978_volume));
	//printk("111\n");
	return 0;

}



irqreturn_t ar7240_i2s_intr(int irq, void *dev_id)
//irq_handler_t ar7240_i2s_intr(int irq, void *dev_id, struct pt_regs *regs)
{
	uint32_t r;
	//MBOX Rx DMA completion (one descriptor completed) interrupts
	r = ar7240_reg_rd(MBOX_INT_STATUS);
   
    if(r & RX_UNDERFLOW)
        stats.rx_underflow++;

	/* Ack the interrupts */
	ar7240_reg_wr(MBOX_INT_STATUS, r);

	

	return IRQ_HANDLED;
}

void ar7240_i2sound_i2slink_on(int master)
{

    ar7240_reg_wr(AR7240_STEREO_CONFIG,
        (AR7240_STEREO_CONFIG_SPDIF_ENABLE|
        AR7240_STEREO_CONFIG_ENABLE|
        AR7240_STEREO_CONFIG_RESET|
        AR7240_STEREO_CONFIG_PCM_SWAP|
        AR7240_STEREO_CONFIG_MIC_WORD_SIZE|
		AR7240_STEREO_CONFIG_MODE(0)|
        AR7240_STEREO_CONFIG_DATA_WORD_SIZE(AR7240_STEREO_WS_16B)|
		AR7240_STEREO_CONFIG_I2S_32B_WORD|
		AR7240_STEREO_CONFIG_SAMPLE_CNT_CLEAR_TYPE|
        AR7240_STEREO_CONFIG_MASTER|
		AR7240_STEREO_CONFIG_PSEDGE(2)
        ));//gl-inet
  
    //ar7240_reg_wr(AR7240_STEREO_CLK_DIV,0xec330);//gl-inet
    //ar7240_reg_wr(AR7240_STEREO_CLK_DIV,0xd9013);//gl-inet
    //ar7240_reg_wr(AR7240_STEREO_CLK_DIV,((0x10 << 16) + 0x4600));//gl-inet 48000kHz   
    ar7240_reg_wr(AR7240_STEREO_CLK_DIV,((0x11 << 16) + 0xb6b0));//gl-inet 44100kHz

	//init_wm8978();
    udelay(100);
    ar7240_reg_rmw_clear(AR7240_STEREO_CONFIG, AR7240_STEREO_CONFIG_RESET);
}

void ar7240_i2sound_request_dma_channel(int mode)
{
	ar7240_reg_wr(MBOX_DMA_POLICY, 0x6a);
}

void ar7240_i2sound_dma_desc(unsigned long desc_buf_p, int mode)
{
	/*
	 * Program the device to generate interrupts
	 * RX_DMA_COMPLETE for mbox 0
	 */
	if (mode) {
		ar7240_reg_wr(MBOX0_DMA_TX_DESCRIPTOR_BASE, desc_buf_p);
	} else {
		ar7240_reg_wr(MBOX0_DMA_RX_DESCRIPTOR_BASE, desc_buf_p);
	}
}

void ar7240_i2sound_dma_start(int mode)
{
	// Start
	if (mode) {
		ar7240_reg_wr(MBOX0_DMA_TX_CONTROL, START);
	} else {
		ar7240_reg_wr(MBOX0_DMA_RX_CONTROL, START);
	}
}


void ar7240_i2sound_dma_pause(int mode)
{
	//Pause
    if (mode) {
        ar7240_reg_wr(MBOX0_DMA_TX_CONTROL, PAUSE);
    } else {
        ar7240_reg_wr(MBOX0_DMA_RX_CONTROL, PAUSE);
    }
}

void ar7240_i2sound_dma_resume(int mode)
{
	/*MBOX_STATUS
    	 * Resume
      */
     if (mode) {
     	ar7240_reg_wr(MBOX0_DMA_TX_CONTROL, RESUME);
     } else {
        ar7240_reg_wr(MBOX0_DMA_RX_CONTROL, RESUME);
     }
}

loff_t ar7240_i2s_llseek(struct file *filp, loff_t off, int whence)
{
	printk(KERN_CRIT "llseek\n");
	return off;
}
struct file_operations ar7240_i2s_fops = {
	.owner = THIS_MODULE,
	.llseek = ar7240_i2s_llseek,
	.write = ar9100_i2s_write,
	.unlocked_ioctl = ar7240_i2s_ioctl,
	.open = ar7240_i2s_open,
	.release = ar7240_i2s_close,
	.read = ar7240_i2s_read,
};

int ar7240_i2s_init_module(void)
{
	unsigned long flags;
	//int result = -1;
	ar7240_i2s_softc_t *sc = &sc_buf_var;
	
	sc->sc_irq = AR7240_MISC_IRQ_DMA;
#if 0

	/* Establish ISR would take care of enabling the interrupt */
	result = request_irq(sc->sc_irq, ar7240_i2s_intr, IRQF_DISABLED,"ar7240_i2s", NULL);
	if (result) {
		printk(KERN_INFO"i2s: can't get assigned irq %d returns %d\n",sc->sc_irq, result);	
	}
#endif	
	local_irq_save(flags);
	glzt_set_gpio_to_l3();
	glzt_set_gpio_to_iis();
 	local_irq_restore(flags);

	init_s3c2410_iis_bus(); 
	
	init_wm8978();

	
	audio_dev_dsp = register_sound_dsp(&ar7240_i2s_fops, -1);
	
	audio_dev_mixer = register_sound_mixer(&smdk2410_mixer_fops, -1);

	I2S_LOCK_INIT(&sc_buf_var);
	return 0;		/* succeed */
    
}

void ar7240_i2s_cleanup_module(void)
{
	//ar7240_i2s_softc_t *sc = &sc_buf_var;
	//free_irq(sc->sc_irq, NULL);
	unregister_sound_dsp(audio_dev_dsp);
	unregister_sound_mixer(audio_dev_mixer);
}
module_init(ar7240_i2s_init_module);
module_exit(ar7240_i2s_cleanup_module);
