#' @title inter network
#' @description Computes intercellular gene networks.
#'
#' @param data a data frame of n rows (genes) and m columns (cells) of read or UMI counts (note : rownames(data)=genes)
#' @param genes a character vector of HUGO official gene symbols of length n
#' @param cluster a numeric vector of length m
#' @param signal a list (result of the **cell_signaling()** function)
#' @param c.names (optional) cluster names
#' @param species "homo sapiens" or "mus musculus"
#' @param write a logical (if TRUE writes graphML and text files for the interface and internal networks)
#' @param verbose a logical
#'
#' @return The function returns a list containing the intercellular networ).
#'
#' @export
#'
#' @importFrom igraph graph_from_data_frame set_vertex_attr write.graph V %>%
#' @import data.table
#'
#' @examples
#'m = data.frame(cell.1=runif(10,0,2),cell.2=runif(10,0,2),cell.3=runif(10,0,2),
#'cell.4=runif(10,0,2),cell.5=runif(10,0,2),cell.6=runif(10,0,2),cell.7=runif(10,0,2))
#'rownames(m) = paste("gene", 1:10)
#'cluster = c(1,1,1,2,3,3,2)
#'inter_network(m,rownames(m),cluster,signal=NULL)
inter_network = function(data,genes,cluster,signal,c.names=NULL,species=c("homo sapiens","mus musculus"),write=TRUE,verbose=TRUE){
  if (dir.exists("networks")==FALSE & write==TRUE){
    dir.create("networks")
  }
  if (is.null(c.names)==TRUE){
    c.names <- paste("cluster",1:max(cluster))
  }
  if (min(cluster)!=1){
    cluster = cluster + 1 - min(cluster)
  }
  if (length(c.names)!=max(cluster) | sum(duplicated(c.names))>0 | grepl("/",paste(c.names,collapse =""))){
    cat("The length of c.names must be equal to the number of clusters and must contain no duplicates. The cluster names must not include special characters",fill=TRUE)
    return()
  }
  cellint=NULL
  rownames(data) <- genes
  interface <- list()

  species <- match.arg(species)
  if (species=='mus musculus'){
    mm2Hs <- mm2Hs[!is.na(mm2Hs$`Mouse orthology confidence`) & mm2Hs$`Mouse orthology confidence`==1,c(3,5)]
    mm2Hs <- subset(mm2Hs,!duplicated(mm2Hs$`Gene name`))
    mm2Hs <- subset(mm2Hs,mm2Hs$`Mouse gene name`!="a")
    Hs2mm <- mm2Hs[,1]
    mm2Hs <- mm2Hs[,2]
    names(mm2Hs) <- Hs2mm
    names(Hs2mm) <- as.character(mm2Hs)
    m.names <- mm2Hs[rownames(data)]
    data <- subset(data,(!is.na(m.names)))
    m.names <- m.names[!is.na(m.names)]
    rownames(data)<-as.character(m.names)
  }

  # Interface networks =========================================================================
  tmp <-  vector("list",length = length(signal))
  if (is.null(signal)==FALSE){
    for (i in 1:length(signal)){
      ci <-  signal[[i]]
      from <- names(ci)[1]
      to <- names(ci)[2]
      tmp[[i]] <-  data.frame(ligand=paste0(from,".",ci[[1]]),receptor=paste0(to,".",ci[[2]]),ligand.name=ci[[1]],
                 receptor.name=ci[[2]],origin=from,destination=to,ci[,3:4],stringsAsFactors=FALSE)
    }
    cellint = do.call("rbind",tmp)

    # Pair networks ----------------
    m <- 0
    n.int <- NULL
    for (i in 1:(length(signal))){
      m <- m+1
      subpop <- colnames(signal[[i]])[1]
      other <- colnames(signal[[i]])[2]
      cell.n <- cellint[cellint$origin==subpop & cellint$destination==other,]
      n.int=c(n.int,paste(subpop, other, sep="-"))
      if (verbose==TRUE){
        cat("Doing",subpop,"and",other,"...")
      }

      l.both <- intersect(cell.n$ligand[cell.n$origin==subpop],cell.n$ligand[cell.n$origin==other])
      for (l in l.both){
        k <- which(cell.n$ligand==l & cell.n$origin==other)
        cell.n$ligand[k] <- paste("bis",l)
      }
      r.both <- intersect(cell.n$receptor[cell.n$origin==subpop],cell.n$receptor[cell.n$origin==other])
      for (r in r.both){
        k <- which(cell.n$receptor==r & cell.n$origin==other)
        cell.n$receptor[k] <- paste("bis",r)
      }

      if (is.null(dim(cell.n))==FALSE){
        g.cell <- graph_from_data_frame(cell.n,directed=TRUE)
        genes <- c(cell.n$ligand,cell.n$receptor)
        prop.genes <- unique(data.frame(gene=genes,display.name=gsub("^bis ","",genes),gene.type=c(rep("ligand",nrow(cell.n)),rep("receptor",nrow(cell.n))),expressed.in=c(cell.n$origin,cell.n$destination),stringsAsFactors=FALSE))
        prop.genes <- subset(prop.genes,!duplicated(prop.genes[[1]]))
        rownames(prop.genes) <- prop.genes[[1]]
        g.cell <- g.cell %>% set_vertex_attr(name="display.name",value=prop.genes[V(g.cell)$name,"display.name"]) %>% set_vertex_attr(name="gene.type",value=prop.genes[V(g.cell)$name,"gene.type"]) %>% set_vertex_attr(name="expressed.in",value=prop.genes[V(g.cell)$name,"expressed.in"])

        if (write==TRUE){
          write.graph(g.cell,file=paste0('./networks/intercell_network_',subpop,'-',other,'.graphml'),format="graphml")
        }
        interface[[m]]=cell.n
      } else {
        interface[[m]]="No network"
      }
      cat(' OK', fill=TRUE)
    }
    names(interface) = n.int


    # Full network ----------------
    g.cell <- graph_from_data_frame(cellint[,c(1,2,7,8)],directed=TRUE)
    genes <- c(cellint$ligand,cellint$receptor)
    prop.genes <- unique(data.frame(gene=genes,display.name=c(cellint$ligand.name,cellint$receptor.name),
                                    gene.type=c(rep("ligand",nrow(cellint)),rep("receptor",nrow(cellint))),stringsAsFactors=FALSE))
    prop.genes <- subset(prop.genes,!duplicated(prop.genes[[1]]))
    rownames(prop.genes) <- prop.genes[[1]]
    g.cell <- g.cell %>% set_vertex_attr(name="display.name",value=prop.genes[V(g.cell)$name,"display.name"]) %>% set_vertex_attr(name="gene.type",value=prop.genes[V(g.cell)$name,"gene.type"])
    prop.genes <- unique(data.frame(gene=genes,display.name=c(cellint$ligand.name,cellint$receptor.name),
                                    expressed.in=c(cellint$origin,cellint$destination),stringsAsFactors=FALSE))
    prop.genes <- subset(prop.genes,!duplicated(prop.genes[[1]]))
    rownames(prop.genes) <- prop.genes[[1]]
    g.cell <- g.cell %>% set_vertex_attr(name="expressed.in",value=prop.genes[V(g.cell)$name,"expressed.in"])
    if (write==TRUE){
      write.graph(g.cell,file=paste0('./networks/full-intercellular-network.graphml'),format="graphml")
    }
  }
  res = list(interface,cellint[,c(1,2,7,8)])
  names(res) = c("individual-networks","full-network")
  return(res)
}



#' simplifyInteractions
#'
#' @param t the network to be simplified
#' @param lr ligand receptor interactions
#' @param autocrine a logical
#'
#' @return t
#' @export
#'
#' @examples
#' t=data.frame(a.gn=c("CEP63","CEP63"),b.gn=c("MZT2A","DYNC1L2"),
#' type=c("in-complex-with","in-complex-with"))
#' simplifyInteractions(t)
simplifyInteractions <- function(t,lr=NULL,autocrine=FALSE){

  mergeText <- function(a,b){
    if (length(a)==0)
      b
    else
      if (length(b)==0)
        a
    else
      paste(union(strsplit(a,';')[[1]],strsplit(b,';')[[1]]),collapse=';')
  }


  t$detailed.type <- t$type

  # reduce interaction types
  t$type[t$type %in% c('interacts-with','in-complex-with')] <- 'complex'
  t$type[t$type %in% c('chemical-affects','consumption-controlled-by','controls-expression-of','controls-phosphorylation-of','controls-production-of','controls-state-change-of','controls-transport-of','controls-transport-of-chemical')] <- 'control'
  t$type[t$type %in% c('catalysis-precedes','reacts-with','used-to-produce')] <- 'reaction'

  # merge duplicated interactions with same reduced type
  key <- paste(t$a.gn,t$b.gn,t$type,sep='|')
  dk <- which(duplicated(key))
  for (i in dk){
    jj <- setdiff(which(t$a.gn==t[i,"a.gn"] & t$b.gn==t[i,"b.gn"] & t$type==t[i,"type"]),i)
    for (j in jj){
      t[j,"pmid"] <- mergeText(t[j,"pmid"],t[i,"pmid"])
      t[j,"pathway"] <- mergeText(t[j,"pathway"],t[i,"pathway"])
      t[j,"detailed.type"] <- mergeText(t[j,"detailed.type"],t[i,"detailed.type"])
    }
  }
  if (length(dk)>0)
    t <- t[-dk,]

  # promote interaction types in case one interaction is still given for multiple "reduced" interaction types
  key <- paste(t$a.gn,t$b.gn,sep='|')
  dk <- which(duplicated(key))
  for (i in dk){
    jj <- setdiff(which(t$a.gn==t[i,"a.gn"] & t$b.gn==t[i,"b.gn"]),i)
    for (j in jj){
      t[j,"pmid"] <- mergeText(t[j,"pmid"],t[i,"pmid"])
      t[j,"pathway"] <- mergeText(t[j,"pathway"],t[i,"pathway"])
      t[j,"detailed.type"] <- mergeText(t[j,"detailed.type"],t[i,"detailed.type"])
      if (t$type[j]!='control'){
        if (t$type[i]=='control' || t$type[i]=='complex')
          t$type[j] <- t$type[i]
      }
    }
  }
  if (length(dk)>0)
    t <- t[-dk,]

  # eliminate reverse interactions
  l.key <- paste(t$a.gn,t$b.gn,sep='|')
  r.key <- paste(t$b.gn,t$a.gn,sep='|')
  rk <- which(r.key%in%l.key)
  to.remove <- NULL
  for (i in rk){
    j <- setdiff(which(t$a.gn==t[i,"b.gn"] & t$b.gn==t[i,"a.gn"]),i)
    if (j < i){
      t[j,"pmid"] <- mergeText(t[j,"pmid"],t[i,"pmid"])
      t[j,"pathway"] <- mergeText(t[j,"pathway"],t[i,"pathway"])
      t[j,"detailed.type"] <- mergeText(t[j,"detailed.type"],t[i,"detailed.type"])
      if (t$type[j]!='control'){
        if (t$type[i]=='control'){
          t$type[j] <- 'control'
          t$a.gn[j] <- t$a.gn[i]
          t$b.gn[j] <- t$b.gn[i]
        }
        else
          if (t$type[i]=='complex')
            t$type[j] <- 'complex'
      }
      to.remove <- c(to.remove,i)
    }
  }
  if (length(to.remove)>0)
    t <- t[-to.remove,]

  # interactions between 2 ligands or 2 receptors are removed unless 'complex'
  bad <- ((t$a.gn%in%lr$ligand & t$b.gn%in%lr$ligand) | (t$a.gn%in%lr$receptor & t$b.gn%in%lr$receptor)) & t$type!='complex'
  t <- t[!bad,]

  if (!autocrine && !is.null(lr)){
    # remove LR pairs
    bad <- (t$a.gn%in%lr$ligand & t$b.gn%in%lr$receptor) | (t$a.gn%in%lr$receptor & t$b.gn%in%lr$ligand)
    t <- t[!bad,]
  }

  return(t)
}


