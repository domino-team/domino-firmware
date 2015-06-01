/*
 *Utility for playing and recording  wav file using
 *Atheros I2S device
 *Written by Jacob Philip
 * Rewritten by Varada ;)
 */

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <sys/signal.h>
#include <sys/types.h>
#include <sys/ipc.h>
#include <sys/sem.h>
#include <sys/shm.h>
#include <sys/wait.h>
#include <sys/types.h>
#include <sys/ioctl.h>
#include <fcntl.h>
#include <signal.h>

#include "i2sio.h"

#define BUFF_SIZE	(NUM_DESC * I2S_BUF_SIZE)

typedef struct {
	u_int	data_chunk;	/* 'data' */
	u_int	data_length;	/* samplecount (lenth of rest of block?) */
} scdata_t;

typedef struct {
	u_int		main_chunk;	/* 'RIFF' */
	u_int		length;		/* Length of rest of file */
	u_int		chunk_type;	/* 'WAVE' */
	u_int		sub_chunk;	/* 'fmt ' */
	u_int		sc_len;		/* length of sub_chunk */
	u_short		format;		/* should be 1 for PCM-code */
	u_short		modus;		/* 1 Mono, 2 Stereo */
	u_int		sample_fq;	/* frequence of sample */
	u_int		byte_p_sec;
	u_short		byte_p_spl;	/* samplesize; 1 or 2 bytes */
	u_short		bit_p_spl;	/* 8, 12 or 16 bit */
	/*
	 * FIXME:
	 * Apparently, two different formats exist.
	 * One with a sub chunk length of 16 and another of length 18.
	 * For the one with 18, there are two bytes here.  Don't know
	 * what they mean.  For the other type (i.e. length 16) this
	 * does not exist.
	 *
	 * To handle the above issue, some jugglery is done after we
	 * read the header
	 *		-Varada (Wed Apr 25 14:53:02 PDT 2007)
	 */
	u_char		pad[2];
	scdata_t	sc;
} __attribute__((packed)) wavhead_t;

char *audev = "/dev/dsp";
int audio, bufsz, fine, dbg, recorder = 0;
int valfix = -1, mclk_sel = 0;	/* Audio parameters */

#define dp(...)	do { if (dbg) { fprintf(stderr, __VA_ARGS__); } } while(0)
#define ep(...)	do { fprintf(stderr, __VA_ARGS__); } while(0)

#if __BYTE_ORDER == __BIG_ENDIAN
#	if !defined(__NetBSD__)
#		include <byteswap.h>
#	else
#		include <sys/bswap.h>
#		define bswap_32 bswap32
#		define bswap_16 bswap16
#	endif
#endif

void signal_handler(sig)
        int sig;
{
   switch(sig) {
   case SIGHUP:
        break;
   case SIGTERM:
        exit(0);
        break;
   case SIGCHLD:
        exit(0);
        break;
    }
}


void pause_handler(int iSignal)
{
    signal(SIGUSR1, pause_handler);

    printf("Pausing.........\n");
    if (ioctl(audio, I2S_PAUSE, recorder) < 0) {
        perror("I2S_PAUSE");
    }
}


void resume_handler(int iSignal)
{
    signal(SIGUSR2, resume_handler);

    printf("Resuming.........\n");
    if (ioctl(audio, I2S_RESUME, recorder) < 0) {
        perror("I2S_RESUME");
    }
}


int
record (int fd)
{
    wavhead_t   hdr;
    scdata_t    sc;
    int     ret=0, count=0, i=0;
    char        *audiodata;
    u_char      *tmp;

    if (fd < 0) {
        return EINVAL;
    }

    /*
     * Header needs to be formulated....
     */

    hdr.main_chunk = 0x52494646;	// RIFF
    hdr.length = 0xe6822700;
    hdr.chunk_type = 0x57415645;	// WAVE
    hdr.sub_chunk = 0x666d7420;		// fmt
    hdr.sc_len = 0x12000000;
    hdr.format = 0x100;
    hdr.modus = 0x200; 
    hdr.sample_fq = 0x44ac0000;
    hdr.byte_p_sec = 0x10b10200;
    hdr.byte_p_spl = 0x400;
    hdr.bit_p_spl =  0x1000;
    hdr.pad[0] = 0x0;
    hdr.pad[1] = 0x0;
    hdr.sc.data_chunk = 0x64617461;
    hdr.sc.data_length = 0xc0822700; // 0x00945228 to be tested for long hrs record

    write(fd, &hdr, sizeof (hdr));

#if __BYTE_ORDER == __BIG_ENDIAN
    hdr.length  = bswap_32(hdr.length);
    hdr.sc_len  = bswap_32(hdr.sc_len);
    hdr.format  = bswap_16(hdr.format);
    hdr.modus   = bswap_16(hdr.modus);
    hdr.sample_fq   = bswap_32(hdr.sample_fq);
    hdr.byte_p_sec  = bswap_32(hdr.byte_p_sec);
    hdr.byte_p_spl  = bswap_16(hdr.byte_p_spl);
    hdr.bit_p_spl   = bswap_16(hdr.bit_p_spl);
#endif

    /*
     * Refer to the comments in the declaration of the wavhead_t
     * structure.
     * Having a pointer and moving around would have been easier.
     * But, that results in unaligned reads for the 32bit integer
     * data resulting in core dump.  Hence...
     * -Varada
     */

    if (hdr.sc_len == 16) {
        tmp = &hdr.pad[0];
        lseek(fd, -2, SEEK_CUR);
    } else if (hdr.sc_len == 18) {
        tmp = &hdr.pad[2];
    } else {
        return EINVAL;
    }
    memcpy(&sc, tmp, sizeof(sc));

#if __BYTE_ORDER == __BIG_ENDIAN
    sc.data_chunk = bswap_32 (sc.data_chunk);
    sc.data_length = bswap_32 (sc.data_length);
#endif

    if (bufsz <= 0) {
        bufsz = BUFF_SIZE;
    }

    audiodata = (char *) malloc (bufsz * sizeof (char));
    if (audiodata == NULL) {
        return ENOMEM;
    }

    do {
        /*
         * Bug#:    26972
         * The byte stream after the `.wav' header could have
         * additional data (like author, album etc...) apart
         * from the actual `audio data'.  Hence, ensure that
         * extra stuff is not written to the device.  Stop at
         * wherever the audio data ends.
         *  +--------+----------------------+--------+
         *  | header | audio data . . . . . | extras |
         *  +--------+----------------------+--------+
         */
        count = bufsz;

eagain:
        ret = read (audio, audiodata, count);
        if (ret < 0 && errno == EAGAIN) {
            printf("record %d, error %d \n", __LINE__, ret);
            goto eagain;
        }

        if ((write(fd, audiodata, ret)) < 0)  {
            printf("record %d, error %d \n", __LINE__, ret);
            perror("Read audio data");
            break;
        }


        i += ret;

    } while (i <= sc.data_length);

    free (audiodata);

    return 0;
}


int
playwav (int fd)
{
	wavhead_t	hdr;
	scdata_t	sc;
	int		tmpcount, ret=0, count=0, i;
	char		*audiodata, *data;
	u_char		*tmp;

	if (fd < 0) {
		return EINVAL;
	}

	read(fd, &hdr, sizeof (hdr));

#if __BYTE_ORDER == __BIG_ENDIAN
	hdr.length	= bswap_32(hdr.length);
	hdr.sc_len	= bswap_32(hdr.sc_len);
	hdr.format	= bswap_16(hdr.format);
	hdr.modus	= bswap_16(hdr.modus);
	hdr.sample_fq	= bswap_32(hdr.sample_fq);
	hdr.byte_p_sec	= bswap_32(hdr.byte_p_sec);
	hdr.byte_p_spl	= bswap_16(hdr.byte_p_spl);
	hdr.bit_p_spl	= bswap_16(hdr.bit_p_spl);
#endif

	/*
	 * Refer to the comments in the declaration of the wavhead_t
	 * structure.
	 * Having a pointer and moving around would have been easier.
	 * But, that results in unaligned reads for the 32bit integer
	 * data resulting in core dump.  Hence...
	 * -Varada
	 */
	if (hdr.sc_len == 16) {
		tmp = &hdr.pad[0];
		lseek(fd, -2, SEEK_CUR);
	} else if (hdr.sc_len == 18) {
		tmp = &hdr.pad[2];
	} else {
		return EINVAL;
	}
    memcpy(&sc, tmp, sizeof(sc));

#if __BYTE_ORDER == __BIG_ENDIAN
	sc.data_chunk = bswap_32 (sc.data_chunk);
	sc.data_length = bswap_32 (sc.data_length);
#endif

	if (bufsz <= 0) {
		bufsz = BUFF_SIZE;
	}
	//printf("bufsz:%d \n",bufsz);

	

	if (ioctl(audio, I2S_FREQ, hdr.sample_fq) < 0) {
		perror("I2S_FREQ");
	}

	if (ioctl(audio, I2S_DSIZE, hdr.bit_p_spl) < 0) {
		perror("I2S_DSIZE");
	}
    if (mclk_sel) {
	    if (ioctl(audio, I2S_MCLK, mclk_sel) < 0) {
	    	perror("I2S_MCLK");
	    }
	}

	audiodata = (char *) malloc (bufsz * sizeof (char));
	if (audiodata == NULL) {
		return ENOMEM;
	}
	//sc.data_length = 2093012;

	for (i = 0; i <= sc.data_length; i += bufsz) {
		/*
		 * Bug#:	26972
		 * The byte stream after the `.wav' header could have
		 * additional data (like author, album etc...) apart
		 * from the actual `audio data'.  Hence, ensure that
		 * extra stuff is not written to the device.  Stop at
		 * wherever the audio data ends.
		 *	+--------+----------------------+--------+
		 *	| header | audio data . . . . . | extras |
		 *	+--------+----------------------+--------+
		 */
		count = bufsz;
		//printf("sc.data_length:%d \n",sc.data_length);
		//printf("count0:%d \n",count);
		if ((i + count) > sc.data_length) {
			count = sc.data_length - i;
		}
		//printf("count1:%d \n",count);
		if ((count = read (fd, audiodata, count)) <= 0) {
			//perror("Read audio data 123\n");
			//printf("Read audio data 123\n");
			//printf("count2:%d \n",count);
			break;
		}

#ifdef WASP
        tmpcount = count;
        data = audiodata;
        ret = 0;
        if (valfix != -1) {
            memset(data, valfix, tmpcount);
        }
erestart:
        ret = write(audio, data, tmpcount);
        if (ret == -ERESTART) {
            goto erestart;
        }
#else
eagain:                                                         
        tmpcount = count;                                       
        data = audiodata;                                       
        ret = 0;                                                
        do {                                                    
            ret = write(audio, data, tmpcount);                     
            if (ret < 0 && errno == EAGAIN) {                       
                dp("%s:%d %d %d\n", __func__, __LINE__, ret, errno);
                goto eagain;                                        
            }                                                       
            tmpcount = tmpcount - ret;                              
            data += ret;                                            
        } while(tmpcount);                                      
#endif
		dp("i = %d\n", i);
	}

	free (audiodata);

	return 0;
}

int
main (int argc, char *argv[])
{

	int	fd,		/* The file descriptor */
		optc,		/* For getopt */
        counter,
        i,
        ret,
        child;
    char option;

	bufsz = 0;
	fine=-2;

	while ((optc = getopt (argc, argv, "mrpv:t:d:f:")) != -1) {
		switch (optc) {
			printf("111");
			case 'v': 
				valfix = atoi (optarg);
				printf("getopt v");
				break;
			case 't': 
				bufsz = atoi (optarg);
				printf("getopt t"); 
				break;
			case 'd': 
				audev = optarg;
				printf("getopt d");  
				break;
			case 'f':
				fine = atoi(optarg);
				if (fine < -1 || fine > 1) {
					ep("Fine tuning in this level is not "
					   "supported. Will play in default\n");
					fine = 0;
				}
				printf("getopt f"); 
				break;
			case 'p': /* Turn on prints */
				dbg = 1;
				printf("getopt p"); 
				break;
			case 'r':
				recorder = 1;
				printf("getopt r"); 
				break;
            case 'm':
                mclk_sel = 1;
		printf("getopt m"); 
                break;
			default: 
			ep("Unknown option\n"); 
			printf("getopt Unknown option"); 			
			exit(-1);
		}
	}

    audio = open (audev, (recorder) ? O_RDONLY : O_WRONLY);

	if (audio < 0) {
		ep("Device %s opening failed\n", audev);
		exit (-1);
	}
	//printf("222\n");

	if (recorder) {
		if ((fd = open(
                    argv[optind], O_CREAT | O_TRUNC | O_WRONLY
								)) == -1) {
			perror(argv[optind]);
			exit(-1);
		}
	} else {
		if ((fd = open (argv[optind], O_RDONLY)) == -1) {
			perror(argv[optind]);
			exit(-1);
		}
	}
	//printf("333\n");
    signal(SIGUSR1, pause_handler);
    signal(SIGUSR2, resume_handler);

    if(recorder) {
	    record(fd);
    } else {
	    playwav(fd);
    }
	//printf("444\n");
	close(fd);
rep:
	ret = close(audio);
	if (errno == EAGAIN) {
		dp("%s:%d %d %d\n", __func__, __LINE__, ret, errno);
		goto rep;
	}
	return 0;
}
