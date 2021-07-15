#!/bin/bash
#========================================================
# PROJET : LRRtransfert
# SCRIPT : candidateLoci.sh
# AUTHOR : Celine Gottin & Thibaud Vicat
# CREATION : 2020.02.20
#========================================================
# DESCRIPTION : Use of mmseqs to find regions of interest in the target genome from protein sequences contained in LRRome 
#				and create query/target pairs
#               returns this LRRome 
# ARGUMENTS : o $1 : Target genome
#			  o $2 : Path to LRRome 
#			  o $3 : Path to a text file with 4 columns :
#                    First column contain a code the accession.
#                    Second column contain a path to the reference GFF containing LRR 
#                    Third column contain a path to the referene asembly (fasta format)
#                    Fourth column is not obligatory and should contain a path to a file containing information for LRR (family and class of each location)
#			  o $4 : Launch directory
# DEPENDENCIES : o python3
#========================================================
#                Environment & variables
#========================================================
BLASTDB=$1
LRRome=$2
CDNA=$LRRome/REF_cDNA
GFF=$(cat $3| cut -f2)
PROTEINS=$LRRome/REF_PEP
CDS=$LRR/REF_CDS
SPECIES=$(cat $3| cut -f1)
treshold1=$(cat $3| cut -f5)
treshold2=$(cat $3| cut -f6)
SCRIPT='/SCRIPT'
function extractSeq {
	##Extracting each sequence from a fasta in separate files
	gawk -F"[;]" '{if($1~/>/){line=$1;gsub(">","");filename=$1;print(line) > filename}else{print > filename}}' $1
}
function filter_Blastp {
	##filtering blastp results;remove redonduncies (Hit insides an other hit);concatenate consecutive blast hit modifying stat
	sort -k1,1 -Vk7,7 $1 | gawk -F"\t" 'BEGIN{OFS="\t"}{
		if(FNR==1){
			Q=$1;S=$2;L=$4;Qstart=$5;Qend=$6;Sstart=$7;Send=$8;nident=$9;line=$0;}
		else{
			if($1==Q && $2==S){
				if($7>=Send-30 && $8>Send && $5>Qtart && $5>Qend-30){
					$4=($4+L-(Send-$7));
					$5=Qstart;
					$7=Sstart;
					$9=$9+nident;
					$10=($9/$4)*100
					line=$0}}
			else{
				print(line);Q=$1;S=$2;Qstart=$5;Qend=$6;Sstart=$7;Send=$8;nident=$9;line=$0;}}
	}END{print(line)}' > $2
}
          #------------------------------------------#
          # 1. Find Regions of interest with mmseqs2 #
          #------------------------------------------#
mkdir $LRRome/mmseqs
mmseqs createdb $1 $LRRome/mmseqs/${SPECIES}_genome_db -v 0
mmseqs createdb $LRRome/*_proteins.fasta $LRRome/mmseqs/prot_db  -v 0
mmseqs search $LRRome/mmseqs/prot_db $LRRome/mmseqs/${SPECIES}_genome_db resultDB_aln.m8 tmp -s 8.5 -a -e 0.1 --min-length 10 --merge-query 1 --cov-mode 2 --max-seqs 30000 --sequence-overlap 1000 -v 0
mmseqs convertalis $LRRome/mmseqs/prot_db $LRRome/mmseqs/${SPECIES}_genome_db resultDB_aln.m8 $LRRome/mmseqs/res_candidatsLRR_in_$SPECIES.out --format-output query,target,qlen,alnlen,qstart,qend,tstart,tend,nident,pident,gapopen,evalue,bits  -v 0
cat $LRRome/mmseqs/res_candidatsLRR_in_$SPECIES.out > res_candidatsLRR_in_$SPECIES.out
## Build up global hits by proteins in 2 steps: 1st round with high thresholds to fix "anchor" exons
## Then second round with weaker hsp to complete the areas at the ends and define other paralogous type areas

## 1st run : high threshold
## filtering and Sorting
gawk -v treshold1=$treshold1 'BEGIN{OFS="\t"}{if($10>=treshold1){print($0)}}' res_candidatsLRR_in_$SPECIES.out | sort -k1,2 -Vk7,7 > sort_65_candidatsLRR_in_$SPECIES.out
## If an alignment gives the totality of the sequence -> extraction region
## if not, is the next hit close?... yes -> accumulation
## if cumulative alignment < $treshold1 of the prot --> eliminate
## Set intron size with max intron in Nip for the prot
gawk 'BEGIN{OFS="\t"}{
		if(NR==FNR){
			if($3=="gene"){gsub("ID=","",$9);new=1;ID=$9}
			else{
				if($3=="CDS"){
					if(new==1){stop=$5;new=0;MAX_INTRON[ID]=0}
					else{
						if($4-stop>MAX_INTRON[ID]){MAX_INTRON[ID]=($4-stop)};stop=$5}}}}
		else{if($7<$8){strand="+"}else{strand="-"};
		limIntron=5000;if(MAX_INTRON[$1]>limIntron){limIntron=MAX_INTRON[$1]+500};
		if(FNR==1){Q=$1;T=$2;P1=$7;P2=$8;old5=$5;old6=$6;S=strand;line=$0;}
		else{
			split(line,tab,"\t");
			if($1==Q && $2==T && strand==S && ((strand=="+" && $6>old6 && old6<$5+100) || (strand=="-" && $5<old5 && $6<old5+100)) && ($(7)-P2<limIntron || $(8)-P1<limIntron)){
				P1=$7;P2=$8;
				$4=$4+tab[4];
				old5=$5;
				old6=$6;
				if($5>tab[5]){$5=tab[5]};
				if($6<tab[6]){$6=tab[6]};
				if(strand=="+"){
					if($7>tab[7]){$7=tab[7]};
					if($8<tab[8]){$8=tab[8]};}
				else{
					if($7<tab[7]){$7=tab[7]};
					if($8>tab[8]){$8=tab[8]};}
				$9=$9+tab[9];
				$11=$11+tab[11];
				$13=$13+tab[13]
				$10=($9/$4)*100;
				line=$0;}
			else{
				print(line);Q=$1;T=$2;P1=$7;P2=$8;old5=$5;old6=$6;S=strand;line=$0}}
}}END{print(line)}' $GFF sort_65_candidatsLRR_in_$SPECIES.out | sort -k2,2 -Vk7,7 > concat_65_candidatsLRR_in_$SPECIES.tmp
## 2nd run : lower threshold
gawk -v treshold1=$treshold1 -v treshold2=$treshold2 'BEGIN{OFS="\t"}{if($10>treshold2 && $10<treshold1){print($0)}}' res_candidatsLRR_in_$SPECIES.out | sort -k1,2 -Vk7,7 > sort_45_candidatsLRR_in_$SPECIES.out
##we discarded hits falling inside already identified regions
cat concat_65_candidatsLRR_in_$SPECIES.tmp sort_45_candidatsLRR_in_$SPECIES.out | sort -k1,2 -Vk7,7 | gawk 'BEGIN{OFS="\t"}{if(NR==1){query=$1;target=$2;p7=$7;p8=$8;print}else{if($1!=query || $2!=target || ($7<$8 && $8>p8) || ($7>$8 && $7>p7)){print;p7=$7;p8=$8;query=$1;target=$2}}}' > concat_candidatsLRR_in_$SPECIES.tmp
gawk 'BEGIN{OFS="\t"}{
		if(NR==FNR){
			if($3=="gene"){gsub("ID=","",$9);new=1;ID=$9}
			else{
				if($3=="CDS"){
					if(new==1){stop=$5;new=0;MAX_INTRON[ID]=0}
					else{
						if($4-stop>MAX_INTRON[ID]){MAX_INTRON[ID]=($4-stop)};stop=$5}}}}
		else{if($7<$8){strand="+"}else{strand="-"};
		limIntron=5000;if(MAX_INTRON[$1]>limIntron){limIntron=MAX_INTRON[$1]+500};
		if(FNR==1){Q=$1;T=$2;P1=$7;P2=$8;old5=$5;old6=$6;S=strand;line=$0;}
		else{
			split(line,tab,"\t");
			if($1==Q && $2==T && strand==S && ((strand=="+" && $6>old6 && old6<$5+100) || (strand=="-" && $5<old5 && $6<old5+100)) && ($(7)-P2<limIntron || $(8)-P1<limIntron)){
				P1=$7;P2=$8;
				$4=$4+tab[4];
				old5=$5;
				old6=$6;
				if($5>tab[5]){$5=tab[5]};
				if($6<tab[6]){$6=tab[6]};
				if(strand=="+"){
					if($7>tab[7]){$7=tab[7]};
					if($8<tab[8]){$8=tab[8]};}
				else{
					if($7<tab[7]){$7=tab[7]};
					if($8>tab[8]){$8=tab[8]};}
				$9=$9+tab[9];
				$11=$11+tab[11];
				$13=$13+tab[13]
				$10=($9/$4)*100;
				line=$0;}
			else{
				if((tab[6]-tab[5]+1)/tab[3]>=0.6 && tab[10]>=50){print(line)};Q=$1;T=$2;P1=$7;P2=$8;old5=$5;old6=$6;S=strand;line=$0}}
}}END{print(line)}' $GFF concat_candidatsLRR_in_$SPECIES.tmp | sort -k2,2 -Vk7,7 > concat_candidatsLRR_in_$SPECIES.out
## Regions candidates per query --> filter to remove redundancies
## Keep for an area of interest, the query giving the best coverage 
gawk -F"\t" 'BEGIN{OFS="\t"}{
       if(NR==1){T=$2;P1=$7;P2=$8;score=$(13);line=$0}
       else{
          if($2==T && ($(7)<P2 || P1>$(8))){
              if(score<$(13)){T=$2;P1=$7;P2=$8;score=$(13);line=$0} 
          }else{
              print(line);T=$2;P1=$7;P2=$8;line=$0;score=$(13)}}
}END{print(line)}' concat_candidatsLRR_in_$SPECIES.out > filtered_candidatsLRR_in_$SPECIES.out
gawk -F"\t" 'BEGIN{OFS="\t";}{if(NR==FNR){CHR[FNR]=$2;if($7<$8){START[FNR]=$7;STOP[FNR]=$8}else{START[FNR]=$8;STOP[FNR]=$7}}
                            else{if($2!=CHR[FNR-1]){s1="0";current=$2}else{s1=STOP[FNR-1]};
								 if($2!=CHR[FNR+1]){if($7<$8){s2=$8+5000}else{s2=$7+5000}}else{s2=START[FNR+1]};print($0,s1,s2)}}' filtered_candidatsLRR_in_$SPECIES.out filtered_candidatsLRR_in_$SPECIES.out > filtered_candidatsLRR_in_$SPECIES.out2
# Extract regions of interest + 300bp before and after
# gff format and query/target list
gawk -v sp=$SPECIES 'BEGIN{OFS="\t";}{
           if($7<$8){
               if($5>10){$7=$7-3000}else{$7=$7-300};
               if($7<=$(14)){$7=$(14)+1};
               if($6<$3-10){$8=$8+3000}else{$8=$8+300};
			   if($8>=$(15)){$8=$(15)-1};
               pos=sprintf("%08d",$7);
               print($2,"TransfertAnnot","gene",$7,$8,".","+",".","ID="sp"_"$2"_"pos";Origin="$1);print(sp"_"$2"_"pos,$1,"+")>"liste_query_target.txt"}
           else{
               if($6<$3-10){$8=$8-3000}else{$8=$8-300};
			   if($8<=$(14)){$8=$(14)+1};
               if($5>10){$7=$7+3000}else{$7=$7+300};
               if($7>=$(15)){$7=$(15)-1};
               pos=sprintf("%08d",$7);
               print($2,"TransfertAnnot","gene",$8,$7,".","-",".","ID="sp"_"$2"_"pos";Origin="$1);print(sp"_"$2"_"pos,$1,"-")>"liste_query_target.txt"}
}' filtered_candidatsLRR_in_$SPECIES.out2 > filtered_candidatsLRR_in_$SPECIES.gff
cat liste_query_target.txt > candidate_loci_to_LRRome
cat filtered_candidatsLRR_in_$SPECIES.gff > filtered_candidatsLRR
python3 $SCRIPT/Extract_sequences_from_genome.py -f $BLASTDB -g filtered_candidatsLRR_in_$SPECIES.gff -o ./DNA_candidatsLRR_in_$SPECIES.fasta  -t gene 
cat ./DNA_candidatsLRR_in_$SPECIES.fasta > xDNA_candidatsLRR_in 
mkdir CANDIDATE_SEQ_DNA ; cd CANDIDATE_SEQ_DNA
extractSeq ../DNA_candidatsLRR_in_$SPECIES.fasta
