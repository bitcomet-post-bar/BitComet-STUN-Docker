#!/bin/bash
read LINE
PORT=$(echo $LINE | awk -F ':|,' '{print$3}')
exec socat - TCP:127.0.0.1:$PORT
