#!/bin/sh

# begin with a bunch of spaces, then has +, - or ~, then another space
# change to: begin with +, - or ~, then a bunch of spaces
# change the ~ to ! (github diff style)

sed -e 's;\(^ *\)\([\~|\+|\-]\) ;\2\1 ;g' -e 's;^\~;\!;g' $1
