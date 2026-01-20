#!/bin/bash


defaultPath="./"
files=$(ls $1 || $defaultPath)



echo $files

for file in $files; do
    if [ -d "$1$file" ]; then

        echo "$1$file is a directory."
    
    elif [ -f "$1$file" ]; then
        echo "$1$file is a file."
    
        if [[ $1$file == *.sh ]]; then
    
            mkdir -p "$1Scripts/"
            mv "$1$file" "$1Scripts/"
            echo "$1$file is a shell script."
    
        elif [[ $1$file == *.txt ]] || [[ $1$file == *.md ]]; then
    
            mkdir -p "$1Documents/"
            mv "$1$file" "$1Documents/"
            echo "$1$file is a text file."
    
        elif [[ $1$file == *.jpg ]] || [[ $1$file == *.png ]]; then
    
            mkdir -p "$1Images/"
            mv "$1$file" "$1Images/"
            echo "$1$file is an image file."
    
        else
    
            echo "$1$file is of an unknown file type."
    
        fi
    
    else
    
        echo "$1$file is neither a file nor a directory."
    
    fi

done
