# -*- coding: utf-8 -*-
"""
Created on Mon Feb 20 16:14:07 2020

@author: gottince
"""

#----------------------------------#
#    DESCRIPTION
#----------------------------------#

# Read table gene model file from annotation transfert output and test for canonical model
# Retrieve gene ID for wich non-canonical model is detected

#----------------------------------#
#    PARAMETRES
#----------------------------------#
# - File name of input genomic fasta
# - File name of input Table gene file 
# - File name of output Table gene file (with corrected intron)

import argparse
import csv
from Bio import SeqIO



parser = argparse.ArgumentParser()

parser.add_argument("-f","--fasta", type=str, help="Exact path of genomic fasta file")
parser.add_argument("-t","--table", type=str, help="Exact path of feature table file")

args = parser.parse_args()



#----------------------------------#
#            FUNCTIONS
#----------------------------------#

def isCanonicalIntron_forward(DNA_dict,Chr,startIntron,stopIntron) :
    "Check if donnor and acceptor splice sites are canonical in forward strand"
    donnor=DNA_dict[Chr][startIntron:startIntron+2] ##GT
    acceptor=DNA_dict[Chr][stopIntron-3:stopIntron-1] ##AG
    #print("donnor=",donnor.seq," acceptor=",acceptor.seq)
    if((donnor.seq=="GT" or donnor.seq=="GC") and acceptor.seq=="AG") :
        return True
    else :
        return False
 

def isCanonicalIntron_reverse(DNA_dict,Chr,startIntron,stopIntron) :
    "Check if donnor and acceptor splice sites are canonical in reverse strand"
    donnor=DNA_dict[Chr][stopIntron-3:stopIntron-1] ##AC
    acceptor=DNA_dict[Chr][startIntron:startIntron+2] ##CT
    #print("donnor=",donnor.seq," acceptor=",acceptor.seq)
    if((donnor.seq=="AC" or donnor.seq=="CG") and acceptor.seq=="CT") :
        return True
    else :
        return False  


def isStart(Seq) :
    if (Seq=="ATG") :
        return True
    else :
        return False


def isStop(Seq) :
    if (Seq=="TGA" or Seq=="TAG" or Seq=="TAA") :
        return True
    else :
        return False




#----------------------------------#
#              MAIN
#----------------------------------#

print("Chr\tProtID\tPBstart\tPBstop\tOF\tPBintron\tvalidity")

## Read genome
chr_dict = SeqIO.to_dict(SeqIO.parse(args.fasta, "fasta"))

## read table with one gene per line / one line per gene
gff=open(args.table, mode='r')
gff_reader = csv.reader(gff, delimiter=';')

for row in gff_reader :
    start=""
    stop=""
    toCheck=False
    frameshift=False
    notCanonic=False
    myProt=row[0]
    strand=row[1]
    Chr='_'.join(row[0].split("_")[1:-1]) ## Chromosome Id
    #Chr=row[0].split("_")[0] ## pour Nip

    if(strand=="+") :
        ## Check start and stop
        start=chr_dict[Chr][int(row[2])-1:int(row[2])+2].seq
        stop=chr_dict[Chr][int(row[-1])-3:int(row[-1])].seq
        if( not isStart(start) or not isStop(stop)) :
            toCheck=True
        ## Check intron/frameshift
        ## if frameshift or (intron and not canonical intron)
        for i in range(3,len(row)-2,2) :
            if(int(row[i+1])<int(row[i])) :
                toCheck=True
                frameshift=True
            elif(int(row[i+1])>int(row[i])+10 and not isCanonicalIntron_forward(chr_dict,Chr,int(row[i]),int(row[i+1]))) :
                toCheck=True
                notCanonic=True

    else :
        ## Check start and stop
        stop=chr_dict[Chr][int(row[2])-1:int(row[2])+2].reverse_complement().seq
        start=chr_dict[Chr][int(row[-1])-3:int(row[-1])].reverse_complement().seq
        if( not isStart(start) or not isStop(stop)) :
            toCheck=True
        ## Check intron/frameshift
        ## if frameshift or (intron and not canonical intron)
        for i in range(3,len(row)-2,2) :
            if(int(row[i+1])<int(row[i])):
                toCheck=True
                frameshift=True
            elif(int(row[i+1])>int(row[i])+10 and not isCanonicalIntron_reverse(chr_dict,Chr,int(row[i]),int(row[i+1]))) :
                toCheck=True
                notCanonic=True

    
    if(toCheck) :
        print(Chr,myProt,not isStart(start),not isStop(stop),frameshift,notCanonic,"notValid",sep='\t')
    else :
        print(Chr,myProt,not isStart(start),not isStop(stop),frameshift,notCanonic,"Valid",sep='\t')
    
gff.close()    
