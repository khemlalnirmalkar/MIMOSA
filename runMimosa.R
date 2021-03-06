#Create a stoichiometric matrix (EMM) and gene abundance matrix from a metagenomic network, and compare with metabolomic data
#assumes already-processed KO and metabolite abundance datasets

library(KEGGREST)
library(data.table)
library(RColorBrewer)
library(qvalue)
library(getopt)
library(ggplot2)
library(mimosa)
library(rmarkdown)
options(stringsAsFactors=F, curl_interrupt = F)
#source("core_functions.R")

spec = matrix(c('genefile','g',1,"character",
              'metfile','m',1,"character",
              'classification','a',0,"logical",
              'write_net','w',0,"logical",
              'file_prefix','p',2,"character",
              'net_method','n',2,"character",
              'net_file','l',2,"character",
              'degree_filter','f',2,"integer",
              'met_id_file','i',2,"character",
              'minpath_file','k',2,"character",
              'cor_method','c',2,"character",
              'num_permute','u',2,"integer",
              'quant','q',2,"double",
              'nonzero_filt','z',2, "integer",
              'mapformula_file','e',2, "character",
              'ko_rxn_file','r',2, "character",
              'rxn_annots_file','x', 2, "character",
              'contribs_file', 'o', 2, "character",
              'keggFile', 'b', 2, "character",
              'taxonomy_file', 't', 2, "character",
              'metadata_file', 'd', 2, "character",
              'metadata_var', 'v', 2, "character",
              'contrib_no_copy_num', 'y', 2, "logical",
              'spec_method', 'sm', 2 ,"character",
              'summary_doc_dir', 'sd', 2, "character" ), byrow=T, ncol=4)

opt = getopt(spec, opt = commandArgs(TRUE))

datasets = read_files(opt$genefile, opt$metfile)
genes = datasets[[1]]
mets = datasets[[2]]
write_net = T
# if(opt$write_net) write_net = T else write_net = F
# cat(paste("Write_net is ",write_net,"\n"))
if(!is.null(opt$file_prefix)) file_prefix = opt$file_prefix else file_prefix = 'net1'
cat(paste("File prefix is ", file_prefix,"\n"))

if(!is.null(opt$net_method)) net_method = opt$net_method else net_method = 'KeggTemplate' #loadNet or KeggTemplate
cat(paste("Net method is ", net_method,"\n"))
if(!is.null(opt$degree_filter)) degree_filter = opt$degree_filter else degree_filter = 30
cat(paste("Degree filter is", degree_filter,"\n"))

met_id_file = ""
minpath_file = ''

if(!is.null(opt$cor_method)) cor_method = opt$cor_method else cor_method = "spearman"
cat(paste("Mantel correlation method is ",cor_method,"\n"))
if(net_method == "loadNet"){
  if(!is.null(opt$net_file)) net_file = opt$net_file
  cat(paste("Network file is ",net_file,"\n"))
} else if(net_method == "KeggTemplate"){
  if(is.null(opt$mapformula_file)){
    stop("Need mapformula file!")
  } else{
    #Set up generic network info
    if(!is.null(opt$keggFile)){
      rxn_table = fread(opt$keggFile) #should be correctly formatted reaction table
    } else{
      cat("Generating network template from KEGG...\n")
      if(is.null(opt$ko_rxn_file) & is.null(opt$keggFile)){ ##Use KEGGREST
        all_kegg = get_kegg_reaction_info("KEGGREST", kolist = genes[,KO])
      } else{
        if(is.null(opt$rxn_annots_file)){
          stop("If using downloaded KEGG files for reaction info, must provide a file linking KOs to reactions and a file with reaction annotations")
        } else{
          all_kegg = get_kegg_reaction_info(opt$ko_rxn_file, opt$rxn_annots_file)
        }
      }
      rxn_table = generate_network_template_kegg(opt$mapformula_file, all_kegg, write_out = T)
      cat("Got community network!\n")
    }
  }
}
if(!is.null(opt$num_permute)) num_permute = opt$num_permute else num_permute = 20000
cat(paste("Number of Mantel permutations is ", num_permute,"\n"))
if(!is.null(opt$classification)) {
  runmet2 = T
  if(!is.null(opt$quant)) quant = opt$quant else quant = 0.5
  cat(paste("Quantile cutoff for classification is"), quant, "\n")
} else runmet2 = F
if(!is.null(opt$nonzero_filt)) nonzero_filt = opt$nonzero_filt else nonzero_filt = 3
cat(paste("Nonzero filter is ", nonzero_filt,"\n"))
if(!is.null(opt$taxonomy_file)){
  tax_file = opt$taxonomy_file
  sum_to_genus = T
}  else{
  tax_file = ""
  sum_to_genus = F
}
if(!is.null(opt$spec_method)){
  spec_method = opt$spec_method
} else {
  spec_method = "cmps"
}
cat(paste("Identifying species contributors by comparing with ", spec_method, "\n"))

cat("Running main MIMOSA analysis\n")
if(!runmet2){
  results1 = run_all_metabolites(genes, mets, file_prefix = file_prefix, id_met = !is.null(opt$met_id_file), met_id_file = met_id_file,
                    net_method = net_method, net_file = net_file, rxn_table_source = rxn_table,
                    correction = "fdr", degree_filter = degree_filter, minpath_file = minpath_file, cor_method = cor_method, nperm = num_permute, nonzero_filter = nonzero_filt)
} else {
  results1 = run_all_metabolites2(genes, mets, file_prefix = file_prefix, id_met = !is.null(opt$met_id_file), met_id_file = met_id_file,
                       net_method = net_method, net_file = net_file,  rxn_table_source = rxn_table,
                       correction = "fdr", degree_filter = degree_filter, minpath_file = minpath_file, quant = quant, nonzero_filter = nonzero_filt)

}

### Get potential key species contributors, assumes PICRUSt was used to generate metagenome predictions
## If using Greengenes, can change to sum_to_genus = T and will evaluate at the genus level instead of the OTU level
if(!is.null(opt$contribs_file)){
  cat("Getting potential species contributors to metabolite variation\n")
  if(!is.null(opt$contrib_no_copy_num)){
    spec_contribs = get_spec_contribs(opt$contribs_file, data_dir = getwd(), results_file = paste0(file_prefix, "_out.rda"), out_prefix = file_prefix, otu_id = "all", valueVar = "RelAbundSample", sum_to_genus = sum_to_genus, write_out = T, taxonomy_file = tax_file, comparison = spec_method, met_data = mets) #will also save to file
  } else {
    spec_contribs = get_spec_contribs(opt$contribs_file, data_dir = getwd(), results_file = paste0(file_prefix, "_out.rda"), out_prefix = file_prefix, otu_id = "all", valueVar = "singleMusicc", sum_to_genus = sum_to_genus, write_out = T, taxonomy_file = tax_file, comparison = spec_method, met_data = mets) #will also save to file
  }
}

### Get key gene/reaction contributors across all species
cat("Getting potential gene and reaction contributors to metabolite variation\n")
load(paste0(file_prefix, "_out.rda"))
good_mets = node_data[,compound]
subjects = names(mets)[names(mets) != "KEGG"]
cmps = get_cmp_scores(ko_net[[1]], norm_kos)
cmps_sub_good = cmps[compound %in% good_mets]
all_rxns = lapply(good_mets, function(x){ return(get_non_rev_rxns(ko_net[[3]][Reac==x | Prod==x], by_species = F))})
all_gene_contribs = lapply(1:length(good_mets), gene_contributions, cmps_sub_good = cmps_sub_good, all_rxns = all_rxns,
       subjects=subjects, norm_kos = norm_kos, ko_net = ko_net)
all_ko_cors = rbindlist(lapply(all_gene_contribs, function(x){ return(x[[1]])}))
all_comp_info = rbindlist(lapply(all_gene_contribs, function(x){ return(x[[2]])}))
write.table(all_ko_cors, file = paste0(file_prefix, "_geneContribAnalysis.txt"), quote = F, row.names = F, sep = "\t")
write.table(all_comp_info, file = paste0(file_prefix, "_geneContribCompoundSummary.txt"), quote = F, row.names = F, sep = "\t")
save(all_gene_contribs, file = paste0(file_prefix, "_geneContribs.rda"))

### Run 500 network shuffling tests to evaluate information gained from network structure
# for(j in 1:500){
#   cat(paste0("Running network shuffling test, iteration ", j ,"\n"))
#   run_shuffle(paste0(file_prefix, "_out.rda"), id_num = j)
# }

#Summarize results

cat("Generating summary plots and tables...\n")
if(!is.null(opt$summary_doc_dir)){
  doc_path = opt$summary_doc_dir
} else {
  doc_path = ""
}

#Allow for summarize running in a different directory
out_dir = dirname(normalizePath(paste0(file_prefix, "_nodes.txt")))
file_prefix = basename(file_prefix)

contribs_file = normalizePath(opt$contribs_file)
met_file = normalizePath(opt$metfile)
metadata_file = normalizePath(opt$metadata_file)

## Make sure pandoc is available in order to generate the summary document
if(rmarkdown::pandoc_available()){
  rmarkdown::render(paste0(doc_path, "summarizeMIMOSAresults.Rmd"), rmarkdown::html_document(), params = list(run_prefix = paste0(out_dir, "/", file_prefix), contribs_file = contribs_file, met_file = met_file, metadata_file = metadata_file, metadata_var = opt$metadata_var))
file.rename(paste0(doc_path, "summarizeMIMOSAresults.html"), paste0(out_dir, "/", file_prefix, "_summary.html"))
} else {
  cat(paste("Pandoc not found, summary document could not be generated. Generate it in RStudio by opening summarizeMimosaResults.Rmd, selecting Knit With Parameters, and providing the following parameters:\n",
    "run_prefix:", paste0(out_dir, "/", file_prefix), "\n",
    "contribs_file:", contribs_file, "\n",
    "met_file:", met_file, "\n",
    "metadata_file:", metadata_file, "\n",
    "metadata_var:", opt$metadata_var, "\n",
    sep="\t"))
}
