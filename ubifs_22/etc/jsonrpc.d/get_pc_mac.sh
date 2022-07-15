#!/bin/sh

ip neighbor | grep $1 |awk '{print $5}'
