#!/bin/bash

echo "Hello, My name is Scrypt!"
echo "How are you today?"

read -p "Enter your name: " name

if [ -z "$name" ]; then
    echo "You didn't enter a name."
else
    echo "Nice to meet you, $name!"
fi
