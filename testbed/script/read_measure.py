#!/usr/bin/env python

import sys
import os
from os.path import isfile, join
from collections import defaultdict 
import matplotlib.pyplot as plt
import numpy as np
import matplotlib.patches as mpatches
from matplotlib.font_manager import FontProperties

if len(sys.argv) < 4:
    print('Need gen directory file')
    print('Need target svg field name')
    print('If sort exp name <y/n>')
    print('Example: ./read_measure.py output tokio-runtime-w y')
    sys.exit(1)

def get_service_time(gen_file):
    with open(gen_file) as f:
        tokens = f.readline().split()
        name = tokens[0]
        num_msg = int(tokens[2])
        time_ns = int(tokens[4])
        return (name, num_msg, time_ns)

def extract_percentage_from_svg_line(line):
    name = line[7:].split()[0]
    idx = line.find('%')
    for i in reversed(range(idx)):
        if line[i] == ' ':
            percent = float(line[i:idx])
            return name, percent

def get_cpu_percentage(cpu_path, field):
    percents = defaultdict(float)
    idle_percent = 0.0
    with open(cpu_path) as f:
        for line in f:
            if line[1:6] == 'title':
                if field in line:
                    idx = line.find('%')
                    for i in reversed(range(idx)):
                        if line[i] == ' ':
                            percents['interest-'+field] = float(line[i:idx])
                            break
                if 'wrk:worker' in line:
                    name, percent = extract_percentage_from_svg_line(line)               
                    percents[name] += percent
                if 'do_idle' in line:
                    name, idle_percent = extract_percentage_from_svg_line(line)               
                    percents[name] += idle_percent
    if sum(percents.values()) > 100.0:
        print('Error. svg file percent extraction wrong. Percent higher than 100.')
        print('Possibly. overlapping stacks with common name are added')
        sys.exit(1)
    return percents

def read_exp(exp_path):  #iterate_instances
    exp_data = {} # key is interest, value is value
    instance_dirs = []
    for g in os.listdir(exp_path):
        filepath = os.path.join(exp_path, g)
        # get instances
        if os.path.isdir(filepath):
            instance_dirs.append(filepath)
        # get cpu from svg plot, data source eks
        elif filepath[-3:] == 'svg':
            exp_data['cpus'] = get_cpu_percentage(filepath, field)

    instances = {}
    for instance_dir in instance_dirs: 
        # instances information
        instance_id = os.path.basename(instance_dir)    
        instances[instance_id] = {}
        for f in os.listdir(instance_dir):
            # get service time from instances
            #   process gen latency
            if f == 'gen':
                gen_dir = os.path.join(instance_dir, f)
                service_times = []
                for k in os.listdir(gen_dir):
                    if 'gen' in k:
                        data = get_service_time(os.path.join(gen_dir, k))
                        service_times.append(data)
                instances[instance_id]['service_time']= service_times
                
            # ...  others ...
            # ...

    exp_data['instances'] = instances

    return exp_data

def sort_exp(names):
    exp_types = {}
    exp_gen = {}
    c = defaultdict(list)
    for n in names:
        e = n.find('-')
        d = n.find('gen')
        if d == -1 or e == -1:
            print('Error. Cannot sort experiment name.')
            print('<exp type>-<num>gen-xxxx')
            sys.exit(1)

        exp_type = n[:e]
        exp_gen = int(n[e+1:d])
        c[exp_type].append((n, exp_gen))
  
    sorted_name = []
    for exp_type, names in c.items():
        ss = sorted(names, key=lambda tup: tup[1])
        sorted_name += [s[0] for s in ss]
    return sorted_name 

data_dir = sys.argv[1]
field = sys.argv[2]
is_sort_name = sys.argv[3] == 'y'

# extract data
exps = {}
exp_names = os.listdir(data_dir)
if is_sort_name:
    exp_names = sort_exp(exp_names)

for exp_name in exp_names:
    if exp_name[0] == '.':
        continue
    exp_path = os.path.join(data_dir, exp_name)
    if os.path.isdir(exp_path):
        exp_data = read_exp(exp_path)
    exps[exp_name] = exp_data

print(exps)
# calculate
avg_service = {} # name is exp, value is avg time in ns
cpu_interest = {} # name is exp, value is cpu in dict
gens = defaultdict(list) # data per generator, meaningful comparing fixed index across all gen for fairness

for exp_name in exp_names:
    # get avg service time
    exp_data = exps[exp_name]
    tot_service_time = 0 
    tot_service_msg = 0
    for instance_id, instance_data in exp_data['instances'].items():
        num_gen = len(instance_data['service_time'])
        for data_source, num_msg, service_time in instance_data['service_time']:
            tot_service_time += service_time
            tot_service_msg += num_msg
            gens[(instance_id, data_source)].append(float(service_time)/float(num_msg))
    avg_service[exp_name] = float(tot_service_time)/float(tot_service_msg)/num_gen

# plot 
fig, ax = plt.subplots(nrows=2, ncols=1, figsize=(8,8))
cpu_interest = []
cpu_idle = []
cpu_envoy = []
for exp_name in exp_names:
    exp_data = exps[exp_name]
    envoy_tot = 0
    interest = 0
    print(exp_name, exp_data['cpus'])
    for job, percent in exp_data['cpus'].items():
        if 'interest' in job:
            interest += percent
        elif 'wrk:worker' in job:
            envoy_tot += percent
    cpu_idle.append(exp_data['cpus']['do_idle'])
    cpu_envoy.append(envoy_tot)
    cpu_interest.append(interest)

roc_svc_time = [avg_service[exp_name]/1e6 for exp_name in exp_names]
ax[1].scatter(cpu_interest, roc_svc_time)
ax[1].set_xlabel('app cpu')
ax[1].set_xlim(0,100)
ax[1].set_ylabel('avg service time ms')
for i, txt in enumerate(exp_names):
    ax[1].annotate(txt, (cpu_interest[i], roc_svc_time[i]), ha='center')

width = 0.4
print(len(cpu_interest))
print(len(cpu_idle))
print(len(cpu_envoy))

fontP = FontProperties()
fontP.set_size('xx-small')
ax[0].barh(exp_names, cpu_interest, width, color='r')
ax[0].barh(exp_names, cpu_envoy, width, left=cpu_interest, color='b')
ax[0].barh(exp_names, cpu_idle, width, left=np.array(cpu_interest)+np.array(cpu_envoy), color='g')
tokio_pat =  mpatches.Patch(color='red', label='interested app')
envoy_pat =  mpatches.Patch(color='blue', label='sum-envoy-worker')
idle_pat =  mpatches.Patch(color='green', label='idle')
ax[0].legend(handles=[tokio_pat, envoy_pat, idle_pat], title='cpu category', bbox_to_anchor=(1.05, 1), loc='upper left', prop=fontP)
plt.tight_layout()
plt.savefig(os.path.join(data_dir, 'perf-analysis'))



