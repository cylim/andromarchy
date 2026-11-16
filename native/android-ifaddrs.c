// Part of android-compat.so: getifaddrs() for Android apps.
// glibc's getifaddrs binds its netlink socket and dumps the links (RTM_GETLINK). Android refuses both to apps (bind:
// EACCES on Android 17 whatever the target SDK; links: hidden since Android 11), so it failed, and with it Node's
// os.networkInterfaces() (T3 Code: "Failed to read desktop network interfaces", fatal at startup), Python's
// socket.if_nameindex and others. Like Android's own libc: an unbound socket, the address dump only (RTM_GETADDR,
// allowed), names and flags by ioctl. No AF_PACKET entries: hardware addresses are not available to apps.
#define _GNU_SOURCE
#include <errno.h>
#include <ifaddrs.h>
#include <linux/netlink.h>
#include <linux/rtnetlink.h>
#include <net/if.h>
#include <netinet/in.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <unistd.h>

struct entry { // one allocation per address: freeifaddrs frees it whole
    struct ifaddrs ifa;
    struct sockaddr_storage addr, mask, dst;
    char name[IF_NAMESIZE];
    unsigned index;
    int named;
};

static void set_addr(struct sockaddr_storage *ss, int family, const void *data, unsigned index)
{
    if (family == AF_INET) {
        struct sockaddr_in *s = (struct sockaddr_in *)ss;
        s->sin_family = AF_INET;
        memcpy(&s->sin_addr, data, 4);
    } else {
        struct sockaddr_in6 *s = (struct sockaddr_in6 *)ss;
        s->sin6_family = AF_INET6;
        memcpy(&s->sin6_addr, data, 16);
        if (IN6_IS_ADDR_LINKLOCAL(&s->sin6_addr) || IN6_IS_ADDR_MC_LINKLOCAL(&s->sin6_addr))
            s->sin6_scope_id = index;
    }
}

static void set_mask(struct sockaddr_storage *ss, int family, unsigned prefix)
{
    unsigned char bits[16] = {0};
    for (unsigned i = 0; i < 16 && prefix > 0; i++, prefix -= prefix > 8 ? 8 : prefix)
        bits[i] = prefix >= 8 ? 0xff : (unsigned char)(0xff << (8 - prefix));
    set_addr(ss, family, bits, 0);
}

void freeifaddrs(struct ifaddrs *list)
{
    while (list) {
        struct ifaddrs *next = list->ifa_next;
        free(list);
        list = next;
    }
}

int getifaddrs(struct ifaddrs **out)
{
    struct {
        struct nlmsghdr h;
        struct ifaddrmsg m;
    } req = {.h = {.nlmsg_len = NLMSG_LENGTH(sizeof(struct ifaddrmsg)), .nlmsg_type = RTM_GETADDR,
                   .nlmsg_flags = NLM_F_REQUEST | NLM_F_DUMP, .nlmsg_seq = 1}};
    struct ifaddrs *head = NULL, **tail = &head;
    char buf[16384];
    int err = 0, done = 0;

    *out = NULL;
    int fd = socket(AF_NETLINK, SOCK_RAW | SOCK_CLOEXEC, NETLINK_ROUTE);
    if (fd < 0)
        return -1;
    if (send(fd, &req, req.h.nlmsg_len, 0) < 0) {
        err = errno;
        close(fd);
        errno = err;
        return -1;
    }
    int ctl = socket(AF_INET, SOCK_DGRAM | SOCK_CLOEXEC, 0); // for the interface flags
    while (!done) {
        ssize_t n = recv(fd, buf, sizeof buf, 0);
        if (n < 0 && errno == EINTR)
            continue;
        if (n <= 0) {
            err = n < 0 ? errno : 0;
            break;
        }
        for (struct nlmsghdr *h = (struct nlmsghdr *)buf; NLMSG_OK(h, n); h = NLMSG_NEXT(h, n)) {
            if (h->nlmsg_type == NLMSG_DONE || h->nlmsg_type == NLMSG_ERROR) {
                if (h->nlmsg_type == NLMSG_ERROR)
                    err = -((struct nlmsgerr *)NLMSG_DATA(h))->error;
                done = 1;
                break;
            }
            struct ifaddrmsg *m = NLMSG_DATA(h);
            if (h->nlmsg_type != RTM_NEWADDR || (m->ifa_family != AF_INET && m->ifa_family != AF_INET6))
                continue;
            size_t want = m->ifa_family == AF_INET ? 4 : 16;
            const void *address = NULL, *local = NULL, *broadcast = NULL;
            struct entry *e = calloc(1, sizeof *e);
            if (!e) {
                err = ENOMEM;
                done = 1;
                break;
            }
            int len = IFA_PAYLOAD(h);
            for (struct rtattr *a = IFA_RTA(m); RTA_OK(a, len); a = RTA_NEXT(a, len)) {
                if (a->rta_type == IFA_LABEL)
                    snprintf(e->name, sizeof e->name, "%.*s", (int)RTA_PAYLOAD(a), (char *)RTA_DATA(a));
                else if (RTA_PAYLOAD(a) < want)
                    continue;
                else if (a->rta_type == IFA_ADDRESS)
                    address = RTA_DATA(a);
                else if (a->rta_type == IFA_LOCAL)
                    local = RTA_DATA(a);
                else if (a->rta_type == IFA_BROADCAST)
                    broadcast = RTA_DATA(a);
            }
            // IPv4: IFA_LOCAL is the interface's address, IFA_ADDRESS the peer's on point-to-point links.
            const void *own = local ? local : address;
            if (!own) {
                free(e);
                continue;
            }
            e->index = m->ifa_index;
            e->named = e->name[0] || if_indextoname(m->ifa_index, e->name);
            set_addr(&e->addr, m->ifa_family, own, m->ifa_index);
            set_mask(&e->mask, m->ifa_family, m->ifa_prefixlen);
            e->ifa.ifa_name = e->name;
            e->ifa.ifa_addr = (struct sockaddr *)&e->addr;
            e->ifa.ifa_netmask = (struct sockaddr *)&e->mask;
            if (broadcast || (local && address && memcmp(local, address, want) != 0)) {
                set_addr(&e->dst, m->ifa_family, broadcast ? broadcast : address, m->ifa_index);
                e->ifa.ifa_broadaddr = (struct sockaddr *)&e->dst; // same field as ifa_dstaddr
            }
            *tail = &e->ifa;
            tail = &e->ifa.ifa_next;
        }
    }
    // Only IPv4 addresses carry their interface's name (IFA_LABEL), and Android also refuses the ioctl behind
    // if_indextoname: an IPv6 address takes the name of an IPv4 one on the same interface, else "if<index>".
    for (struct ifaddrs *i = head; i; i = i->ifa_next) {
        struct entry *e = (struct entry *)i;
        for (struct ifaddrs *j = head; j && !e->named; j = j->ifa_next) {
            struct entry *o = (struct entry *)j;
            if (o->named && o->index == e->index) {
                snprintf(e->name, sizeof e->name, "%s", o->name);
                char *alias = strchr(e->name, ':'); // "wlan0:1" labels an alias address
                if (alias)
                    *alias = 0;
                e->named = 1;
            }
        }
        if (!e->named)
            snprintf(e->name, sizeof e->name, "if%u", e->index);
        struct ifreq ifr = {0};
        snprintf(ifr.ifr_name, sizeof ifr.ifr_name, "%s", e->name);
        if (e->named && ctl >= 0 && ioctl(ctl, SIOCGIFFLAGS, &ifr) == 0) {
            i->ifa_flags = (unsigned short)ifr.ifr_flags;
        } else {
            struct sockaddr_in6 *a6 = (struct sockaddr_in6 *)&e->addr;
            int loopback = strcmp(e->name, "lo") == 0 ||
                           (a6->sin6_family == AF_INET6 && IN6_IS_ADDR_LOOPBACK(&a6->sin6_addr));
            i->ifa_flags = IFF_UP | IFF_RUNNING | (loopback ? IFF_LOOPBACK : 0);
        }
    }
    if (ctl >= 0)
        close(ctl);
    close(fd);
    if (err) {
        freeifaddrs(head);
        errno = err;
        return -1;
    }
    *out = head;
    return 0;
}
