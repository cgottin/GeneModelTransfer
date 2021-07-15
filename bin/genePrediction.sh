#!/bin/bash
#========================================================
# PROJET : TransfertGeneModel
# SCRIPT : genePrediction.sh
# AUTHOR : Celine Gottin & Thibaud Vicat
# CREATION : 2020.02.20
#========================================================
# DESCRIPTION : Use of blast and exonerate to predict gene models from query/target pairs and build an annotation based on selected mode
# ARGUMENTS : o $1 : Query/target couple
#             o $2 : Directory with extracted genomic regions of interest
#             o $3 : Target genome
#             o $4 : Selected mode
#             o $5 : Filtered_candidatsLRR
#             o $6 : Path to LRRome
#             o $7 : Launch directory
#             o $8 : Path to a text file with 4 columns :
#                    First column contain a code the accession.
#                    Second column contain a path to the reference GFF containing LRR 
#                    Third column contain a path to the referene asembly (fasta format)
#                    Fourth column is not obligatory and should contain a path to a file containing information for LRR (family and class of each location)
#========================================================
#                Environment & variables
#========================================================
          #------------------------------------------#
          # 1.     Mapping CDS                       #
          #------------------------------------------#
export line=$(echo | cat $1)
echo $line > file
export TARGET_DNA=$2
export BLASTDB=$3
export SPECIES=$(cat $8 | cut -f1)
export mode=$4
export filtered_candidatsLRR=$5
export resDir=$6/Transfert_$SPECIES
export LRRome=$7
export SCRIPT='/GeneModelTransfer.git/branches/container/SCRIPT'
export REF_PEP=$LRRome/REF_PEP
export REF_CDS=$LRRome/REF_CDS
export REF_cDNA=$LRRome/REF_cDNA
export GFF=$(cat $8 | cut  -f2)
echo "$line" > to_transfer_with_cdna.txt
echo "$line" > to_transfer_with_prot.txt
export infoLocus=$(cat $8 | cut  -f4)
mkdir mapping ; cd mapping
function extractSeq {
	##Extracting each sequence from a fasta in separate files
	gawk -F"[;]" '{if($1~/>/){line=$1;gsub(">","");filename=$1;print(line) > filename}else{print > filename}}' $1
}
export -f extractSeq
function mapcds {
   # Param 1 : TARGET = genomic sequence file of interest in the target
   # Param 2 : QUERY = Nip protein ID for mapping in the zone
   cat $REF_CDS/$1* > query.fasta
   blastn -query query.fasta -subject $TARGET_DNA/$2 -outfmt "6 qseqid sseqid qlen length qstart qend sstart send nident pident gapopen" > blastn.tmp
	if [[ -s blastn.tmp ]];then
	cat blastn.tmp >> blastn.save
		## processing results
		# 1. removal of inconsistent matches from the query (sort by id cds Nip, size of aligenement)
		sort -k1,1 -Vrk4,4 blastn.tmp | gawk 'BEGIN{OFS="\t"}{
				if(NR==1){P5=$5;P6=$6;currentCDS=$1;print}
				else{if(($1==currentCDS && $5>P6-10) || $1!=currentCDS){print;P5=$5;P6=$6;currentCDS=$1}}}' > blastn2.tmp
		# 2. output GFF ///// /!\ \\\\\ ATTENTION, the determination of the chromosome depends on the nomenclature of the target
		sort -Vk7,7 blastn2.tmp | gawk 'BEGIN{OFS="\t";cds=1}{
				if(NR==FNR){
					strand[$1]=$3}
				else{
					split($1,M,":");
					split($2,T,"_");
					if(length(T)==3){chr=T[2]}else{chr=T[2]"_"T[3]};
					pos=T[length(T)];
					if(strand[$2]=="+"){deb=(pos+$7-1);fin=(pos+$8-1)}
					else{deb=(pos-$8+1);fin=(pos-$7+1)};
					if(FNR==1){
						print(chr,"blastCDS","gene","0",fin,".",strand[$2],".","ID="$2";origin="M[1]);
						S=$1;P1=$6;P2=$8;
						print(chr,"blastCDS","CDS",deb,fin,".",strand[$2],".","ID="$2":cds"cds);cds=cds+1}
					else{
						if(($1==S && $7>P2-10 && $5>P1-10) || ($1!=S)){
							print(chr,"blastCDS","CDS",deb,fin,".",strand[$2],".","ID="$2":cds"cds);
							cds=cds+1;S=$1;P1=$6;P2=$8;}}}}' ../file - | sed 's/gene/Agene/g' | sort -Vk4,4 | sed 's/Agene/gene/g' > $2.gff
		## blast verification
		python3 $SCRIPT/Extract_sequences_from_genome.py -f $BLASTDB -g $2.gff -o $2.fasta -t prot 2>/dev/null
		blastp -query $2.fasta -subject $REF_PEP/$1 -outfmt "6 qseqid sseqid slen length qstart qend sstart send nident pident gapopen" > blastp.tmp
		cat blastp.tmp >> blastp.save
		#if cov > 97% and pid>75% = ok
		blastForBest=0
		if [[ -s blastp.tmp ]];then
			sh $SCRIPT/filter_Blastp.sh blastp.tmp blastp2.tmp
			check=$(gawk 'NR==1{if(($8-$7+1)/$3>=0.97 && $10>75){print(1)}else{print(0)}}' blastp2.tmp)
			blastForBest=$(gawk 'NR==1{print($10)}' blastp2.tmp)
			covblast=$(gawk 'NR==1{print(($8-$7+1)/$3)}' blastp2.tmp)
		fi
		if [[ $check -eq 1 ]];then
			# Res blast + ajout GFF global
			gawk -F"\t" 'BEGIN{OFS="\t"}{if(NR==FNR){IDENT=$10;COV=($8-$7+1)/$3}
			else{if($3~/gene/){print($0" / pred:mappingCDS / blast-%-ident:"IDENT" / blast-cov:"COV)}
				else{print}}}' blastp.tmp $2.gff > $2_2.gff
			cat $2_2.gff >> mappingCDS_$SPECIES.gff
		
		fi
		#forbest
		gawk -F"\t" 'BEGIN{OFS="\t"}{if(NR==FNR){IDENT=$10;COV=($8-$7+1)/$3}
			else{if($3~/gene/){print($0" / pred:mappingCDS / blast-%-ident:"IDENT" / blast-cov:"COV)}
				else{print}}}' blastp.tmp $2.gff > $2_2.gff
			cat $2_2.gff >> bestMappingCDS_$SPECIES.gff
		rm $2.gff
		rm $2.fasta
	fi
}
export query=$(echo $line | cut -d ' ' -f1)
export target=$(echo $line | cut -d ' ' -f2)
touch mappingCDS_$SPECIES.gff
mapcds $target $query
gawk -F"\t" 'BEGIN{OFS="\t"}{split($9,T,/[=:;]/);if(NR==FNR){if($3=="gene"){max[T[2]]=$5;min[T[2]]=$5}else{if($5>max[T[2]]){max[T[2]]=$5};if($4<min[T[2]]){min[T[2]]=$4}}}else{if($3=="gene"){$4=min[T[2]];$5=max[T[2]]};print}}' mappingCDS_$SPECIES.gff mappingCDS_$SPECIES.gff > tmp ; mv tmp mappingCDS_${SPECIES}.gff
gawk -F"\t" 'BEGIN{OFS="\t"}{split($9,T,/[=:;]/);if(NR==FNR){if($3=="gene"){max[T[2]]=$5;min[T[2]]=$5}else{if($5>max[T[2]]){max[T[2]]=$5};if($4<min[T[2]]){min[T[2]]=$4}}}else{if($3=="gene"){$4=min[T[2]];$5=max[T[2]]};print}}' bestMappingCDS_$SPECIES.gff bestMappingCDS_$SPECIES.gff > tmp ; mv tmp bestMappingCDS_$SPECIES.gff
cd ..
python3 $SCRIPT/Exonerate_correction.py -f $BLASTDB -g ./mapping/mappingCDS_${SPECIES}.gff > mapping_LRRlocus_${SPECIES}.gff
python3 $SCRIPT/Exonerate_correction.py -f $BLASTDB -g ./mapping/bestMappingCDS_$SPECIES.gff > mapping_LRRlocus_best_${SPECIES}.gff
          #------------------------------------------#
          # 2.     Run exonerate cdna2genome         #
          #------------------------------------------#
mkdir exonerate ; cd exonerate
gawk -F"\t" -v species=$SPECIES -v REF_cDNA=$REF_cDNA -v TARGET_DNA=$TARGET_DNA  '{target=$1;query=$2;print("exonerate -m cdna2genome --bestn 1 --showalignment no --showvulgar no --showtargetgff yes --annotation",query".an --query "REF_cDNA"/"query,"--target "TARGET_DNA"/"target,">> LRRlocus_in_"species"_cdna.out")}' ../to_transfer_with_cdna.txt > exe ##cdna
## annotation files
gawk -F"\t" 'BEGIN{OFS="\t"}{if($3=="gene"){start=1;split($9,T,";");id=substr(T[1],4);filename=id".an"}else{if($3=="CDS"){len=$5-$4+1;print(id,"+",start,len)>>filename;start=start+len}}}' $GFF
chmod +x $target.an
chmod +x exe 
./exe
cd ..
export path=$PWD
function parseExonerate {
    # with $1 type of exonerate model --> cdna or prot
    gawk -F"\t" 'BEGIN{OFS="\t"}{if($7=="+" && ($3=="gene" || $3=="similarity")){print}}' $path/exonerate/LRRlocus_in_${SPECIES}_$1.out > $path/exonerate/LRRlocus_in_${SPECIES}_$1.tmp ##prot,cdna
    ## Reconstruct gff from align section
    gawk -F"\t" 'BEGIN{OFS="\t"}{if($3=="similarity"){split($9,T,";");for(i=3;i<=length(T);i++){split(T[i],M," ");start=M[2];end=start+M[4]-1;print(chr,proj,"CDS",start,end,".",strand,".",$9)}}else{print;proj=$2;chr=$1;strand=$7}}' $path/exonerate/LRRlocus_in_${SPECIES}_$1.tmp > $path/exonerate/LRRlocus_in_${SPECIES}_$1.gff ##cdna,prot
   ## define ID and Parent and strand
    gawk -F"\t" 'BEGIN{OFS="\t"}{
               if(NR==FNR){
                  split($9,M,/[=;]/);strand[M[2]]=$7} 
               else{
                  split($1,T,"_");$7=strand[$1];
                  if(length(T)==3){pos=T[3];name=T[2]}else{pos=T[4];name=T[2]"_"T[3]}
                  if(strand[$1]=="+"){
                     $4=pos+$4-1;$5=pos+$5-1}
                  else{
                     o4=$4;o5=$5;$5=pos-o4+1;$4=pos-o5+1};
                  if($3=="gene"){$9="ID="$1};
                  if($3=="CDS"){$3="CDS";$9="Parent="$1};
                  $1=name;print}
}' $filtered_candidatsLRR $path/exonerate/LRRlocus_in_${SPECIES}_$1.gff > filtered_LRRlocus_in_${SPECIES}_$1.gff
    ## Eliminate gene redundancy
    gawk -F"\t" 'BEGIN{OFS="\t"}{if(NR==FNR){if($3=="gene"){if(!START[$9] || $4<START[$9]){START[$9]=$4};if($5>STOP[$9]){STOP[$9]=$5}}}else{if($3=="CDS"){T[$1,$4,$5]++;if(T[$1,$4,$5]==1){print}}else{M[$9]++;if(M[$9]==1){$4=START[$9];$5=STOP[$9];print}}}}' filtered_LRRlocus_in_${SPECIES}_$1.gff filtered_LRRlocus_in_${SPECIES}_$1.gff > filtered2_LRRlocus_in_${SPECIES}_$1.gff
    sed 's/gene/Agene/g' filtered2_LRRlocus_in_${SPECIES}_$1.gff | sort -k1,1 -Vk4,4 -k3,3 | sed 's/Agene/gene/g' > filtered3_LRRlocus_in_${SPECIES}_$1.gff
    ## eliminate redundancy and overlap of CDS if on the same phase (we check the phase by $4 if strand + and by $5 if strand -)
    # 1. remove cds included in other cds and glued cds
	#echo "" >> filtered3_LRRlocus_in_${SPECIES}_$1.gff
	cat filtered3_LRRlocus_in_${SPECIES}_$1.gff > filtered4_LRRlocus_in_${SPECIES}_$1.gff
	gawk -F"\t" 'BEGIN{OFS="\t"}{
		if($3~/gene/){
			print;
			lim=0}
		else{
			if($5>lim){
				print;
				lim=$5}}}' filtered3_LRRlocus_in_${SPECIES}_$1.gff | gawk 'BEGIN{OFS="\t"; line=""}{
		if($3=="gene" ){
			if(line!=""){
				print(line)};
			print;
			lim=0;
			line=""}
		else{
			if($4==(lim+1)){
				$4=old4;
				line=$0;
				lim=$5}
			else{
				if(line!=""){
					print(line)};
				old4=$4;
				line=$0;
				lim=$5}}}END{print(line)}' | gawk -F"\t" 'BEGIN{OFS="\t"}{
		if($5-$4>3){
			print }}' > filtered4_LRRlocus_in_${SPECIES}_$1.gff
	# 2. removal of overlap and intron of less than 15 bases if same phase 
	## check the phase change 
    gawk -F"\t" 'BEGIN{OFS="\t";line=""}{
                if($3~/gene/){if(line!=""){print(line)};print;p=0}
                else{
                   if(p==0){
                       p=1;line=$0;start=$4;stop=$5;mod=($(5)+1)%3}
                   else{
                       if($5<stop+15 || $4<start+15){$4=start;stop=$5;line=$0;mod=($(5)+1)%3}
                       else{
                          if(($4>stop+15) || $4%3!=mod){print(line);line=$0;start=$4;stop=$5;mod=($(5)+1)%3}
                          else{$4=start;stop=$5;line=$0;mod=($(5)+1)%3}
 }}}}END{print(line)}' filtered4_LRRlocus_in_${SPECIES}_$1.gff > filtered5_LRRlocus_in_${SPECIES}_$1.tmp
}
export -f parseExonerate
parseExonerate cdna
#Correct PROT
python3 $SCRIPT/Exonerate_correction.py -f $BLASTDB -g filtered5_LRRlocus_in_${SPECIES}_cdna.tmp > filtered5_LRRlocus_in_${SPECIES}_cdna.gff
# extraction, alignement of prot
python3 $SCRIPT/Extract_sequences_from_genome.py -f $BLASTDB -g filtered5_LRRlocus_in_${SPECIES}_cdna.gff -o PROT_predicted_from_cdna_in_$SPECIES.fasta -t prot 
mkdir Blast
cd Blast
extractSeq ../PROT_predicted_from_cdna_in_$SPECIES.fasta
# generate executable lines
gawk -F"\t" -v species=$SPECIES -v REF_PEP=$REF_PEP 'BEGIN{OFS=""}{query=$1;subject=$2;print("blastp -query ",query," -subject "REF_PEP"/"subject," -outfmt \"6 qseqid sseqid slen length qstart qend sstart send nident pident gapopen\" >> res_predicted_from_cdna_in_",species,".out")}' ../to_transfer_with_cdna.txt > exe
chmod +x exe ; ./exe
sh $SCRIPT/filter_Blastp.sh  res_predicted_from_cdna_in_$SPECIES.out res_predicted_from_cdna_in_$SPECIES.out2
cd ..
# gff with origin info + blast in comment section
gawk -F"\t" 'BEGIN{OFS="\t"}{if(NR==FNR){Nip[$1]=$2;ID[$1]=$10;COV[$1]=($8-$7+1)/$3}else{if($3~/gene/){split($9,T,";");locname=substr(T[1],4);gsub("comment=","",T[2]);$9=T[1];print($0";comment=Origin:"Nip[locname]" / pred:cdna2genome / blast-%-ident:"ID[locname]" / blast-cov:"COV[locname]" / "T[2])}else{print}}}' Blast/res_predicted_from_cdna_in_$SPECIES.out2 filtered5_LRRlocus_in_${SPECIES}_cdna.gff > filtered6_LRRlocus_in_${SPECIES}_cdna.gff
          #------------------------------------------#
          # 3.     Run exonerate prot2genome         #
          #------------------------------------------#
# 4. Transfert with exonerate protein2genome
cd exonerate ; rm exe

gawk -v species=$SPECIES -v REF_PEP=$REF_PEP -v TARGET_DNA=$TARGET_DNA '{target=$1;query=$2;print("exonerate -m protein2genome --showalignment no --showvulgar no --showtargetgff yes -q "REF_PEP"/"query,"-t "TARGET_DNA"/"target,">> LRRlocus_in_"species"_prot.out")}' ../to_transfer_with_prot.txt > exe 
chmod +x exe; ./exe
cd ..
parseExonerate prot
#Correct PROT
python3 $SCRIPT/Exonerate_correction.py -f $BLASTDB -g filtered5_LRRlocus_in_${SPECIES}_prot.tmp > filtered6_LRRlocus_in_${SPECIES}_prot.gff
#### BLAST + add res blast to gff in comment section + method=prot2genome
# extraction, alignment of prot
python3 $SCRIPT/Extract_sequences_from_genome.py -f $BLASTDB -g filtered6_LRRlocus_in_${SPECIES}_prot.gff -o PROT_predicted_from_prot_in_$SPECIES.fasta -t prot 
### blast
cd Blast
rm ${SPECIES}_*
extractSeq ../PROT_predicted_from_prot_in_$SPECIES.fasta
# generate executable lines
rm exe
gawk -F"\t" -v species=$SPECIES -v REF_PEP=$REF_PEP 'BEGIN{OFS=""}{query=$1;subject=$2;print("blastp -query ",query" -subject "REF_PEP"/"subject" -outfmt \"6 qseqid sseqid slen length qstart qend sstart send nident pident gapopen\" > res_predicted_from_prot_in_",species,".out")}' ../to_transfer_with_prot.txt > exe
# launch blasts
chmod +x exe ; ./exe
sh $SCRIPT/filter_Blastp.sh res_predicted_from_prot_in_$SPECIES.out res_predicted_from_prot_in_$SPECIES.out2
prot2genomeForBest=0
prot2genomeForBest=$(gawk 'NR==1{print($10)}' res_predicted_from_prot_in_$SPECIES.out2)
covprot=$(gawk 'NR==1{print(($8-$7+1)/$3)}'  res_predicted_from_prot_in_$SPECIES.out2)
cd ..
# gff with origin info + blast in comment section
gawk -F"\t" 'BEGIN{OFS="\t"}{
       if(NR==FNR){
          Nip[$1]=$2;ID[$1]=$10;COV[$1]=($8-$7+1)/$3}
       else{if($3~/gene/){  
              gsub("comment=","");
              split($9,T,";");
              locname=substr(T[1],4);
              $9=T[1];print($0";comment=Origin:"Nip[locname]" / pred:prot2genome / blast-%-ident:"ID[locname]" / blast-cov:"COV[locname]" / "T[2])}else{print}}}' Blast/res_predicted_from_prot_in_$SPECIES.out2 filtered6_LRRlocus_in_${SPECIES}_prot.gff > filtered7_LRRlocus_in_${SPECIES}_prot.gff

gawk -F"\t" '{
  if(NR==FNR){
    if($10>=70 && ($8-$7+1)/$3>=0.97) {
      OK=1}}
      else{
        if(OK==1)
        {print}}}' Blast/res_predicted_from_cdna_in_$SPECIES.out2  filtered6_LRRlocus_in_${SPECIES}_cdna.gff > filtered7_LRRlocus_in_${SPECIES}_cdna.gff
cdna2genomeForBest=0
cdna2genomeForBest=$(gawk 'NR==1{print($10)}' Blast/res_predicted_from_cdna_in_$SPECIES.out2)
covcdna=$(gawk 'NR==1{print(($8-$7+1)/$3)}'  Blast/res_predicted_from_cdna_in_$SPECIES.out2)
blastbest=$(awk '{print ($1/100)*0.6 + $2*0.4}' <<<"${blastForBest} ${covblast}")
cdnabest=$(awk '{print ($1/100)*0.6 + $2*0.4}' <<<"${cdna2genomeForBest} ${covcdna}")
protbest=$(awk '{print ($1/100)*0.6 + $2*0.4}' <<<"${prot2genomeForBest} ${covprot}")
if [ $mode == "first" ] 
then
	if [ -s mapping_LRRlocus_${SPECIES}.gff ]
	then 
	cat mapping_LRRlocus_${SPECIES}.gff >> $resDir/annotation_transfert_${SPECIES}.gff
	cat mapping_LRRlocus_${SPECIES}.gff > one_candidate_gff
	elif [ -s filtered7_LRRlocus_in_${SPECIES}_cdna.gff ]
	then 
	cat filtered7_LRRlocus_in_${SPECIES}_cdna.gff >> $resDir/annotation_transfert_${SPECIES}.gff
	cat filtered7_LRRlocus_in_${SPECIES}_cdna.gff > one_candidate_gff
	elif [ -s filtered7_LRRlocus_in_${SPECIES}_prot.gff ]
	then 
	cat filtered7_LRRlocus_in_${SPECIES}_prot.gff  >> $resDir/annotation_transfert_${SPECIES}.gff
	cat filtered7_LRRlocus_in_${SPECIES}_prot.gff > one_candidate_gff
	fi
echo ""
elif [ $mode == "best" ]
then
	if [ "$(echo "$blastbest > $cdnabest" | bc -l )" == 1 ] && [ "$(echo "$blastbest > $protbest" | bc -l )" == 1 ] 
	then 
	cat mapping_LRRlocus_best_${SPECIES}.gff >> $resDir/annotation_transfert_${SPECIES}.gff
	cat mapping_LRRlocus_best_${SPECIES}.gff > one_candidate_gff
	elif [ "$(echo "$cdnabest > $blastbest" | bc -l )" == 1 ] && [ "$(echo "$cdnabest > $protbest" | bc -l )" == 1 ] 
	then 
	cat  filtered6_LRRlocus_in_${SPECIES}_cdna.gff >> $resDir/annotation_transfert_${SPECIES}.gff
	cat  filtered6_LRRlocus_in_${SPECIES}_cdna.gff > one_candidate_gff
	else
	cat filtered7_LRRlocus_in_${SPECIES}_prot.gff  >> $resDir/annotation_transfert_${SPECIES}.gff
	cat filtered7_LRRlocus_in_${SPECIES}_prot.gff > one_candidate_gff
	fi
fi
echo $PWD
rm filtered*
rm -r mapping 
rm -r exonerate
rm -r Blast
rm PROT*