#define _POSIX_C_SOURCE 200809L
#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>
static int write_all(int fd,const void *buf,size_t len){const unsigned char*p=buf;while(len){ssize_t n=write(fd,p,len);if(n<0&&errno==EINTR)continue;if(n<=0)return -1;p+=n;len-=(size_t)n;}return 0;}
int main(int argc,char**argv){int port=0,hb=0;for(int i=1;i<argc;i++){if(!strcmp(argv[i],"--port")&&i+1<argc)port=atoi(argv[++i]);else if(!strcmp(argv[i],"--heartbeat"))hb=1;else{fprintf(stderr,"ERROR unknown argument %s\n",argv[i]);return 2;}}if(port<1024||port>65535){fprintf(stderr,"ERROR invalid port\n");return 2;}signal(SIGPIPE,SIG_IGN);int s=socket(AF_INET,SOCK_STREAM,0);if(s<0){fprintf(stderr,"ERROR socket: %s\n",strerror(errno));return 1;}int one=1;setsockopt(s,SOL_SOCKET,SO_REUSEADDR,&one,sizeof(one));struct sockaddr_in a;memset(&a,0,sizeof(a));a.sin_family=AF_INET;a.sin_port=htons((uint16_t)port);a.sin_addr.s_addr=htonl(INADDR_LOOPBACK);if(bind(s,(struct sockaddr*)&a,sizeof(a))<0){fprintf(stderr,"ERROR bind: %s\n",strerror(errno));close(s);return 1;}if(listen(s,4)<0){fprintf(stderr,"ERROR listen: %s\n",strerror(errno));close(s);return 1;}fprintf(stderr,"TCP_LISTENING 127.0.0.1:%d\n",port);fflush(stderr);for(;;){struct pollfd p={s,POLLIN,0};int r=poll(&p,1,hb?1000:-1);if(r<0){if(errno==EINTR)continue;fprintf(stderr,"ERROR poll: %s\n",strerror(errno));break;}if(!r){if(hb&&write_all(STDOUT_FILENO,"R\n",2)<0)break;continue;}int c=accept(s,NULL,NULL);if(c<0){if(errno==EINTR)continue;fprintf(stderr,"ERROR accept: %s\n",strerror(errno));continue;}unsigned char b[2048];for(;;){struct pollfd cp={c,POLLIN,0};int cr=poll(&cp,1,hb?1000:-1);if(cr<0){if(errno==EINTR)continue;break;}if(cr==0){if(hb&&write_all(STDOUT_FILENO,"R\n",2)<0){close(c);close(s);return 1;}continue;}ssize_t n=read(c,b,sizeof(b));if(n<0&&errno==EINTR)continue;if(n<=0)break;if(write_all(STDOUT_FILENO,b,(size_t)n)<0){close(c);close(s);return 1;}}close(c);}close(s);return 1;}
