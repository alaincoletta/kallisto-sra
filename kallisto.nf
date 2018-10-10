/*
 * Copyright (c) 2015-2018, Centre for Genomic Regulation (CRG) and the authors.
 *
 *   This file is part of 'Kallisto-NF'.
 *
 *   Kallisto-NF is free software: you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, either version 3 of the License, or
 *   (at your option) any later version.
 *
 *   Kallisto-NF is distributed in the hope that it will be useful,
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *   GNU General Public License for more details.
 *
 *   You should have received a copy of the GNU General Public License
 *   along with Kallisto-NF.  If not, see <http://www.gnu.org/licenses/>.
 */

/* 
 * Main Kallisto-NF pipeline script
 *
 * @authors
 * Paolo Di Tommaso <paolo.ditommaso@gmail.com>
 * Evan Floden <evanfloden@gmail.com> 
 */


params.transcriptome = "$baseDir/tutorial/transcriptome/transcriptome.fa"
params.name          = "RNA-Seq Abundance Analysis"
params.accession     = "PRJNA162905"
params.fragment_len  = '180'
params.fragment_sd   = '20'
params.bootstrap     = '100'
params.experiment    = "$baseDir/tutorial/experiment/hiseq_info.txt"
params.output        = "results/"


log.info "K A L L I S T O - N F  ~  version 0.9"
log.info "====================================="
log.info "Accession number       : ${params.project}"
log.info "transcriptome          : ${params.transcriptome}"
log.info "fragment length        : ${params.fragment_len} nt"
log.info "fragment SD            : ${params.fragment_sd} nt"
log.info "bootstraps             : ${params.bootstrap}"
log.info "experimental design    : ${params.experiment}"
log.info "output                 : ${params.output}"
log.info "\n"


/*
 * Input parameters validation
 */

transcriptome_file     = file(params.transcriptome)
exp_file               = file(params.experiment) 
projectSRId            = params.project

/*
 * validate input files
 */
if( !transcriptome_file.exists() ) exit 1, "Missing transcriptome file: ${transcriptome_file}"

if( !exp_file.exists() ) exit 1, "Missing experimental design file: ${exp_file}"

int threads = Runtime.getRuntime().availableProcessors()

process getSRAIDs {
    
    cpus 1

    input:
    val projectID from projectSRId
    
    output:
    file 'sra.txt' into sraIDs
    
    script:
    """
    esearch -db sra -query $projectID  | efetch --format runinfo | grep SRR | cut -d ',' -f 1 > sra.txt
    """
}

sraIDs.splitText().map { it -> it.trim() }.set { singleSRAId }

process fastqDump {

    publishDir params.resultdir, mode: 'copy'

    cpus threads

    input:
    val id from singleSRAId

    output:
    set val id, file '*.fastq.gz' into reads

    script:
    """
    parallel-fastq-dump --sra-id $id --threads ${task.cpus} --gzip
    """ 
}


process index {
    input:
    file transcriptome_file
    
    output:
    file "transcriptome.index" into transcriptome_index
      
    script:
    //
    // Kallisto tools mapper index
    //
    """
    kallisto index -i transcriptome.index ${transcriptome_file}
    """
}


process mapping {
    tag "reads: $name"

    input:
    file index from transcriptome_index
    set val(name), file(reads) from read_files

    output:
    file "kallisto_${name}" into kallisto_out_dirs 

    script:
    //
    // Kallisto tools mapper
    //
    def single = reads instanceof Path
    if( !single ) {
        """
        mkdir kallisto_${name}
        kallisto quant -b ${params.bootstrap} -i ${index} -t ${task.cpus} -o kallisto_${name} ${reads}
        """
    }  
    else {
        """
        mkdir kallisto_${name}
        kallisto quant --single -l ${params.fragment_len} -s ${params.fragment_sd} -b ${params.bootstrap} -i ${index} -t ${task.cpus} -o kallisto_${name} ${reads}
        """
    }

}


process sleuth {
    input:
    file 'kallisto/*' from kallisto_out_dirs.collect()   
    file exp_file

    output: 
    file 'sleuth_object.so'
    file 'gene_table_results.txt'

    script:
    //
    // Setup sleuth R dependancies and environment
    //
 
    """
    sleuth.R kallisto ${exp_file}
    """
}



