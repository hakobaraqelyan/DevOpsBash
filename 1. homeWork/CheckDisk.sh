#!/bin/bash

echo "Starting disk check..."   

maxSize=80
diskSize=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')

echo "maxSize is $maxSize"
echo "diskSize is $diskSize"


if [[ $diskSize -le $maxSize ]]; then
    echo "The disk is ${diskSize}% used."

else
    echo "Warning: Disk usage is above ${maxSize}%! Current usage: ${diskSize}%."

fi 

