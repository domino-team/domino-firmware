/*
 * =====================================================================================
 *
 *       Filename:  i2sconf.c
 *
 *    Description:  Application to control i2s device
 *
 *        Version:  1.0
 *        Created:  Tuesday 23 March 2010 04:20:46  IST
 *       Revision:  none
 *       Compiler:  gcc
 *
 *         Author:  YOUR NAME (), 
 *        Company:  
 *
 * =====================================================================================
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

char *audev = "/dev/i2s";


void usage(void)
{
    printf("i2sconf -hmM\n");
    printf("-h : display help message\n");
    printf("-m <1/0> : Enable/Disable external master clock\n");
    printf("-f <44100/48000> : Sampling frequency\n");
}

int main (int argc, char *argv[])
{
    int audio;  
    int mclk_sel = 0;
    int freq = 0;

	int	fd;		    /* The file descriptor */
    int	optc;		/* For getopt */
    int ret;

    audio = open(audev, O_WRONLY);

	if (audio < 0) {
		exit (-1);
	}

	while ((optc = getopt(argc, argv, "hHm:f:")) != -1) {
		switch (optc) {
            case 'm':  
                mclk_sel = atoi(optarg)?1:0;
                if (ioctl(audio, I2S_MCLK, mclk_sel) < 0) {
                    perror("I2S_MCLK");
                }                    
                break;
            case 'f':
                freq = atoi(optarg);
                if (ioctl(audio, I2S_FREQ, freq) < 0) {
                    perror("I2S_FREQ");
                }
                break;
            case 'h':
            case 'H':
                usage();
                break;
			default:   
                break;
		}
	}

rep:
	ret = close(audio);
	if (errno == EAGAIN) {
	    goto rep;
	}
	return 0;
}
