#Necessary packages:NLR-parser, NLR-annotator, BRAKER, samtools, blast, interproscan#

SAMPLES = ["name_of_genome"]
#Making a temp folder#
import os
path = 'tmp'
if not os.path.exists(path):
       os.mkdir(path)

rule all:
     input:
       expand('genome/{sample}.fa', sample=SAMPLES)
#Chopping the genome sequence into overlapping subsequences#
rule chop_sequence:
     input: 
         fa="genome/{sample}.fa"
     output:
         "tmp/{sample}.choppedseq.fa"
     shell: 
         "java -jar ~/NLR-parser/scripts/ChopSequence.jar -i {input.fa} -o {output} \
         -l 20000 -p 5000" 

#Searching the chopped subsequences for pre-determined NLR-associated motifs#
rule step2:
     input:
         "tmp/{sample}.choppedseq.fa"
     output:
         "tmp/{sample}.NLRparser.xml"
     shell:
         "java -jar ~/NLR-parser/scripts/NLR-Parser.jar -t 10 \
        -y ~/anaconda3/envs/NLR_Annotator/bin/meme_4.9.1/bin/mast \
        -x ~/NLR-parser/scripts/meme.xml -i {input} \
        -c {output}"
#Generate the GFF format of NLR loci for the searched motifs#
rule step3:
     input:
         "tmp/{sample}.NLRparser.xml"
     output:
         "tmp/{sample}.NLRparser.gff"
     shell:
         "java -jar ~/NLR-parser/scripts/NLR-Annotator.jar -i {input} \
        -g {output}"
#Make a genome database for detecting nucleotide or protein query sequence#
rule step4:
     input:
         fa="genome/{sample}.fa"
     output:
         "tmp/{sample}.genome_nucl_database"
     shell:
         "makeblastdb -in {input.fa} -dbtype nucl -parse_seqids \
        -out {output}"
#Dectect whether there are genes which cannot be captured by using NLR-parser 
#by using tblastn#
#remember to form a folder which include blastprotein#
rule step5:
     input:
         blastprotein="blastprotein/blastprotein",
         genomebase="tmp/{sample}.genome_nucl_database"
     output:
         "tmp/{sample}.tblastnout.outfmt6"
     shell:
         "tblastn -query {input.blastprotein} -db {input.genomebase} -evalue 0.001 \
         -outfmt 6 > {output}"
#Convert tblastn file into bed, get coloumn 1 2 9 10#
rule step6:
     input:
         "tmp/{sample}.tblastnout.outfmt6"
     output:
         "tmp/{sample}.tblastnout.bed"
     shell:
         """cat {input} | awk "{{print $2"\\t"$9"\\t"$10}}" > {output}"""
#Indexing reference sequence#
rule step7:
     input:
         "genome/{sample}.fa"
     output:
         "genome/{sample}.fa.fai"
     shell:
         "samtools faidx {input}" 
#Create genome file. (?)#
rule step8:
     input:
         "genome/{sample}.fa.fai"
     output:
         "genome/{sample}.genomefile"
     shell:
         "cut -d $'\t' -f1,2 {input} > {output}"
#Generate 20kb flanking BED file for blastx file#
rule step9:
     input:
         bed="tmp/{sample}.tblastnout.bed",
         genomefile="genome/{sample}.genomefile"
     output:
         "tmp/{sample}.tblastn.20kbflanking.bed"
     shell:
         """bedtools slop -b 20000 -s -i {input.bed} \
        -g {input.genomefile} | bedtools sort -i - | bedtools merge \
        -s -d 100 -i - > {output}"""
#Generate 20kb flanking BED file for NLR-parser file#
rule step10:
     input:
         gff="tmp/{sample}.NLRparser.gff",
         genomefile="genome/{sample}.genomefile"
     output:
         "tmp/{sample}.NLRparser.20kbflanking.bed"
     shell:
        """ bedtools slop -b 20000 -s -i {input.gff} -g {input.genomefile} \
        | bedtools sort -i - | bedtools merge -s -d 100 -i - \
        >  {output}"""
#Merge the two bed files (combine blastn.bed and NLRparser.bed into one BED file#
rule step11:
     input:
         tblastn="tmp/{sample}.tblastn.20kbflanking.bed",
         NLRparser="tmp/{sample}.NLRparser.20kbflanking.bed"
     output:
         "tmp/{sample}.all.20kbflanking.bed"
     shell:
         "cat {input.tblastn} {input.NLRparser} \
        | bedtools sort -i - \
        | bedtools merge -d 100 -i - > {output}"
#Convert the merged bed file into fasta format (? required double check)#
rule step12:
     input:
         genome="genome/{sample}.fa",
         flankingbed="tmp/{sample}.all.20kbflanking.bed"
     output:
         "tmp/{sample}.all.20kbflanking.fa"  
     shell:
         "bedtools getfasta -fi {input.genome} -bed {input.flankingbed} \
        > {output}"
#Convert all the sequences in 20kb flanking fasta into uppercase (not sure)#
rule step13:
     input:
         "tmp/{sample}.all.20kbflanking.fa",
     output:
         "tmp/{sample}.all.20kbflanking_upper.fa"
     shell:
         "awk '/^>/ {{print($0)}; /^[^>]/ {print(toupper($0))}}'{input}>{output}"         
#Gene prediction by BRAKER using extended regions around NB-ARCs by 20kb up and downsream#
rule step14:
     input:
         genome="/genome/{sample}.all_20kbflanking_upper.fa",
         prot="tmp/prothint_sequences.fa"
    # output:
     shell:
         "braker.pl --genome={input.genome} \
        --prot_seq={input.prot} \
        --species={sample} --epmode --cores=15 --softmasking --prg=ph \
        --ALIGNMENT_TOOL_PATH=~/anaconda3/envs/braker2/bin/spaln --gff3"
##
##
##


