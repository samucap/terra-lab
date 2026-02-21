#define __FAVOR_BSD      // MUST be first: Tells Mac headers to use common field names
#include <iostream>
#include <cstring>
#include <sys/socket.h>
#include <netinet/in.h>   // Added: Essential for IPPROTO_TCP
#include <netinet/ip.h>
#include <netinet/tcp.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <print>          // C++23: Supported in Clang 21

//Mathematical Checksum Calculation (RFC 793)
unsigned short calculate_checksum(unsigned short *ptr, int nbytes) {
    long sum;
    unsigned short oddbyte;
    short answer;
    sum = 0;
    while (nbytes > 1) {
        sum += *ptr++;
        nbytes -= 2;
    }
    if (nbytes == 1) {
        oddbyte = 0;
        *((u_char*)&oddbyte) = *(u_char*)ptr;
        sum += oddbyte;
    }
    sum = (sum >> 16) + (sum & 0xffff);
    sum = sum + (sum >> 16);
    answer = (short)~sum;
    return answer;
}

int main()
{
    // 1. create a raw socket (requires root)
    int raw_socket = socket(AF_INET, SOCK_RAW, IPPROTO_TCP);
    if (raw_socket < 0) {
        std::cerr << "Failed to create raw socket. are you root?\n";
        return 1;
    }

    // 2. allocate memory for the packet (IP Header + TCP Header)
    char datagram[4096];
    std::memset((void*)datagram, 0, 4096);

    // 3. pointer mapping: cast the memory to our header structs
    struct ip *iph = (struct ip *) datagram;
    struct tcphdr *tcph = (struct tcphdr *) (datagram + sizeof(struct ip));

    // 4. set target
    struct sockaddr_in target;
    target.sin_family = AF_INET;
    target.sin_port = htons(9999);
    inet_pton(AF_INET, "127.0.0.1", &target.sin_addr);

    // 5. build the IP Header
    iph->ip_v = 4;
    iph->ip_hl = 5;
    iph->ip_len = sizeof(struct ip) + sizeof(struct tcphdr);
    iph->ip_id = htons(7777);
    iph->ip_ttl = 255;
    iph->ip_p = IPPROTO_TCP;
    iph->ip_dst.s_addr = target.sin_addr.s_addr; // source IP

    // 6. build the TCP Header
    tcph->th_sport = htons(9998);
    tcph->th_dport = htons(9999);
    tcph->th_seq = 0;
    tcph->th_ack= 0;
    tcph->th_off = 5; // TCP header size
    tcph->th_flags = TH_SYN; // THIS IS SYN FLAG
    tcph->th_win = htons(5840);

    // 7. calculate checksum (mandatory for TCP)
    tcph->th_sum = 0; // set to 0 b4 calculation

    // 8. fire packet
    int sent = sendto(raw_socket, "HERROOOOOOOOOOOOOOOOOOOOOOOOOOOOO", iph->ip_len, 0, (struct sockaddr *) &target, sizeof(target));
    if (sent > 0) {
        std::cout << "[+] Raw SYN packet sent successfully (" << sent << " bytes ).\n";
    }

    close(raw_socket);
    return 0;
}
