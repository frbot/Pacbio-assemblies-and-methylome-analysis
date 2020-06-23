#! /bin/sh

#Convert bax to bam files, only if you are dealing with RSII dataset and ask to provide the path for raw data
rawpath="$1"
/opt/pacbio/smrtlink/smrtcmds/bin/bax2bam *.bax.h5 -o pacbio_reads ;

#Extract fastq files from bam [to be used as input for canu assembly]
bamtools convert -format fastq -in pacbio_reads.subreads.bam -out pacbio_reads.subreads.fastq ;

#Canu assembly [with or without nanopore]
canu -p organism -d directory genomeSize=2.8m -pacbio-raw pacbio_reads.subreads.fastq  
cp directory/organism.unitigs.fasta reference.fasta ;

#Index fasta
samtools faidx reference.fasta ;

#Align subreads to a reference
/opt/pacbio/smrtlink/smrtcmds/bin/pbalign --concordant --hitPolicy=randombest --minAccuracy 70 --minLength 50 --algorithmOptions="--minMatch 12 --bestn 10 --minPctIdentity 70.0" pacbio_reads.subreads.bam reference.fasta aligned_subreads.bam ;

#Polishing with BLASR and quiver
/opt/pacbio/smrtlink/smrtcmds/bin/variantCaller -j 8 --algorithm=quiver --referenceFilename=reference.fasta -o consensus.fasta -o consensus.fastq aligned_subreads.bam ;

#Assembly-coverage
samtools depth aligned_subreads.bam |  awk '{sum+=$3} END { print "Average coverage = ",sum/NR}' > assembly_coverage 2>/dev/null ;

#Obtain ipdsummary
/opt/pacbio/smrtlink/smrtcmds/bin/ipdSummary aligned_subreads.bam \
  --reference reference.fasta \
  --gff basemods.gff \
  --csv basemods.csv \
  --bigwig basemods.wig \
  --pvalue 0.01 \
  --numWorkers 20 \
  --identify m4C,m6A \
  --minCoverage 3 \
  --methylMinCov 10 ;

#Find motifs and refine
/opt/pacbio/smrtlink/smrtcmds/bin/motifMaker find \
  -f reference.fasta \
  -g basemods.gff \
  -m 30 \
  -o motifs.csv \
  -p \
  2>&1 | tee -a motifMaker_find_log.txt ;

/opt/pacbio/smrtlink/smrtcmds/bin/motifMaker reprocess \
  -f reference.fasta \
  -g basemods.gff \
  --minFraction 0 \
  -m motifs.csv \
  -o motifs.gff ;
  
/opt/pacbio/smrtlink/smrtcmds/bin/summarizeModifications basemods.gff ;
