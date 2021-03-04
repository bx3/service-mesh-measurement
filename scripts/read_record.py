#!/usr/bin/env python
import sys
import matplotlib.pyplot as plt
from collections import namedtuple
from collections import defaultdict

Packet = namedtuple('Packet', ['type', 'src', 'dst', 'len', 'lat', 'cpu'])
SockData = namedtuple('SockData', ['sock', 'types', 'send_len', 'recv_len']) #, 'send_lat', 'recv_lat', 'send_cpu', 'recv_cpu'


if len(sys.argv) < 3:
    print('Require. tcpdump file and hostname:port of interests')
    print('Example. record localhost.40000')
    sys.exit(1)

def read_file(filename):
    data = []  
    socks = set()
    with open(filename) as f:
        for line in f:
            if 'IP' in line:
                tokens = line.split()
                p_type = tokens[6]
                src, dst = tokens[2], tokens[4][:-1]
                socks.add(dst)
                length = None
                for i in range(len(tokens)):
                    if 'length' in tokens[i]:
                        length = (tokens[i+1].replace(':', ''))
                push_packet = Packet(p_type, src, dst, length, 0, 0)
                data.append(push_packet)
    return data, socks

def get_header_len(packets, send_sock, recv_sock):
    send_header_len = []
    recv_header_len = []
    types = defaultdict(int)
    for p in packets:
        if recv_sock is not None and recv_sock in p.dst :
            recv_header_len.append(p.len)
        if send_sock is not None and send_sock in p.src :
            send_header_len.append(p.len)
            types[p.type] += 1

    return (send_header_len, recv_header_len, types)

filename = sys.argv[1]
int_socks = sys.argv[2:]

packets, socks = read_file(filename)

socks_data = []
for sock in int_socks:
    send_len, recv_len, types = get_header_len(packets, sock, sock) #'localhost.40000'
    sock_data = SockData(sock, types, send_len, recv_len)
    socks_data.append(sock_data)

for p in socks_data:
    print(p)

