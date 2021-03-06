#' Joins ENM from several partitions, creating a model per algorithm
#'
#' This function reads the models generated either by \code{\link{do_any}} or
#' \code{\link{do_many}} (i.e. one model per partition per algorithm) and
#' summarizes them into a final model for each species-algorithm combination.
#' All the final models are created from the mean of the raw continuous models
#' (\code{raw_mean}). From these means, several
#' outputs can be created, see \code{which_models} for details about
#' the final outputs available. The uncertainty between partitions, taken as
#' ranges (maximum - minimum values) between partitions may also be calculated.
#' Just as there are \emph{no silver bullets in correlative ecological niche
#' modeling}, no method for presenting this models is always better
#' and these are only a subset of the possibilities.
#'
#' @inheritParams setup_sdmdata
#' @param algorithms Character vector specifying which algorithms will be
#' processed. Note that it can have length > 1, ex. \code{c("bioclim", "rf")}.
#' Defaults to NULL: if no name is given it will process all algorithms present
#' in the evaluation files
#' @param mean_th_par A threshold that will be used to cut the raw mean models
#' if \code{which_models} is set to "\code{raw_mean_th}" or to transform the raw
#' mean models into binary models if \code{which_models} is set to
#' "\code{bin_consensus}". Defaults to "\code{spec_sens}" but any \pkg{dismo}
#' threshold can be used (see function \code{\link[dismo]{threshold}}):
#' "\code{kappa}", "\code{no_omission}", "\code{prevalence}",
#' "\code{equal_spec_sens}", "\code{sensitivity}"
#' @param sensitivity The sensitivity value for threshold "\code{sensitivity}".
#'  Defaults to 0.9
#' @param scale_models Logical. Whether input models should be scaled between 0
#' and 1
#' @param consensus_level Which proportion of binary models will be kept when
#' creating \code{bin_consensus}
#' @param models_dir Character. Folder path where the input files are located
#' @param final_dir Character. Name of the folder to save the output files. A
#' subfolder will be created, defaults to "final_model"
#' @param proj_dir Character. The name of the subfolder with the projection.
#' Defaults to "present" but can be set according to the other projections (i.e.
#' to execute the function in projected models)
#' @param which_models Which \code{final_model} will be used? Currently it can
#' be:
#' \describe{
#'   \item{\code{raw_mean}}{Continuous model generated by the mean of the raw
#'   models (scale from 0 to 1)}
#'   \item{\code{raw_mean_th}}{Cuts the \code{raw_mean} by the mean of the
#'   threshold selected in \code{mean_th_par} to make a binary model}
#'    \item{\code{raw_mean_cut}}{Recovers \code{raw_mean} values above the
#'    threshold selected in \code{mean_th_par}. Generates a continuous model
#'    above this threshold while keeping null values below it}
#'   \item{\code{bin_mean}}{The mean of the binary models, created by cutting
#'   the raw mean models by the threshold selected in \code{mean_th_par}.
#'   Generates a model in a discrete scale (0 to 1 in 1/n intervals where n is
#'   the number of partitions)}
#'   \item{\code{bin_consensus}}{The binary consensus from \code{bin_mean}.
#'   Parameter \code{consensus_level} must be defined, 0.5 means a majority
#'   consensus}
#' }
#' @param uncertainty Whether an uncertainty map, measured as range (max-min)
#' should be calculated
#' @param png_final Logical. If \code{TRUE}, writes png files of the final
#' models
#' @param ... Other parameters from \code{\link[raster]{writeRaster}},
#' especially \code{overwrite = TRUE}, when needed
#'
#' @return Returns a data frame with final statistics of the partitions included
#'  in the final model
#' @return Writes on disk a data frame with mean statistics of the partitions
#' included in the final model
#' @return Writes on disk a set of ecological niche models (.tif files) in the
#' \code{final_dir} subfolder
#' @return If \code{png_final = TRUE} writes .png figures in the
#' \code{final_dir} subfolder
#' @seealso \code{\link[dismo]{threshold}}  in \pkg{dismo} package
#' @seealso \code{\link[raster]{writeRaster}}  in \pkg{raster} package
#' @examples
#' \dontrun{
#' # run setup_sdmdata
#' sp <- names(example_occs)[1]
#' sp_coord <- example_occs[[1]]
#' sp_setup <- setup_sdmdata(species_name = sp,
#'                           occurrences = sp_coord,
#'                           predictors = example_vars,
#'                           clean_uni = TRUE)
#'
#' # run do_any
#' sp_bioclim <- do_any(species_name = sp,
#'                      predictors = example_vars,
#'                      algorithm = "bioclim")
#'
#' # run final_model
#' sp_final <- final_model(species_name = sp,
#'                         algorithms = "bioclim",
#'                         which_models = c("bin_consensus"),
#'                         consensus_level = 0.5,
#'                         overwrite = TRUE)
#' }
#' @references
#'     \insertAllCited{}
#' @import raster
#' @importFrom utils read.table write.csv read.csv
#' @export
#'
final_model <- function(species_name,
                        algorithms = NULL,
                        scale_models = TRUE,
                        consensus_level = 0.5,
                        models_dir = "./models",
                        final_dir = "final_models",
                        proj_dir = "present",
                        which_models = c("raw_mean"),
                        mean_th_par = c("spec_sens"),
                        uncertainty = FALSE,
                        png_final = TRUE,
                        sensitivity = 0.9,
                        ...) {
    # Escribe final
    final_folder <- paste(models_dir, species_name, proj_dir,
                        final_dir, sep = "/")
    if (file.exists(final_folder) == FALSE) {
        dir.create(final_folder)
    }
    print(date())
    message(species_name)

    message(paste("Reading evaluation files for", species_name, "in", proj_dir))
    evall <- list.files(
        path = paste0(models_dir, "/", species_name, "/present/partitions"),
        pattern = "^evaluate.+.csv$", full.names = TRUE)
    lista_eval <- lapply(evall, read.csv, header = TRUE, row.names = 1)
    stats <- data.table::rbindlist(lista_eval)
    stats <- data.frame(stats)

    # Extracts only for the selected algorithm
    # if the user doesnt specify, it will take all of them
    if (is.null(algorithms)) {
        algorithms <- unique(stats$algorithm)
    }
    algorithms <- as.factor(algorithms)
    #write stats only for the selected algorithms
    stat_algos <- stats[stats$algorithm %in% algorithms, ]
    write.csv(stat_algos,
              file = paste0(models_dir, "/", species_name, "/present/",
                                   final_dir, "/", species_name,
                                   "_final_statistics.csv"))
    #write mean stats per algorithm
    metrics <- c("kappa", "spec_sens", "no_omission", "prevalence", "equal_sens_spec",
                  "sensitivity", "correlation", "AUC", "AUCratio", "pROC", "TSSmax",
                  "KAPPAmax", "prevalence.value", "PPP", "NPP", "TPR", "TNR", "FPR",
                  "FNR", "CCR", "Kappa", "F_score", "Jaccard")

    stats_summary <- aggregate(stat_algos[,metrics],
                               by = list(
                                   species_name = stat_algos$species_name,
                                   algorithm = stat_algos$algorithm,
                                   dismo_threshold = stat_algos$dismo_threshold
                               ),
                               FUN = mean)
     write.csv(stats_summary, file = paste0(models_dir, "/", species_name, "/present/",
                                            final_dir, "/", species_name,
                                            "_mean_statistics.csv"))
    for (algo in algorithms) {
        final_algo <- raster::stack()
        message(paste("Extracting data for", species_name, algo))
        stats.algo <- stats[stats$algorithm == algo, ]
        #stats.algo <- stats.run[stats.run$algoritmo == algo, ]
        n.part <- nrow(stats.algo)  #How many partitions were there
        #n.part <-  length(unique(stats.algo$partition)) #How many partitions were there
        message(paste("Reading models from .tif files"))
        modelos.cont <-
            list.files(
                path = paste0(models_dir, "/", species_name, "/", proj_dir,
                              "/partitions"),
                full.names = TRUE,
                #pattern = paste0(algo, "_cont_", species_name, "_", run, "_")
                pattern = paste0(algo, "_cont_", ".*tif$")
            )
        mod.cont <- raster::stack(modelos.cont)  #(0)
        sel.index <- seq(1, n.part, 1)
        pond.stats <- rep(1,n.part)
        if (length(sel.index) == 0) {#this should not happen anymore
            message(paste("No partition selected", species_name, algo, proj_dir))
        } else if (length(sel.index) != 0) {
            message(paste(length(sel.index), "/", n.part,
                          "partitions will be used for", species_name, algo))
            if (length(sel.index) == 1) {#this should not happen anymore a menos que sea un solo modelo fitteado
                warning(paste("when only one partition is selected the final models
                          are identical to the original model"))
                cont.sel.1  <- mod.cont[[c(sel.index, sel.index)]]
                pond.stats <- c(pond.stats, pond.stats)#(1)
                }
            if (length(sel.index) > 1) {
                cont.sel.1  <- mod.cont[[sel.index]]  #(1)
                }
            #first column of the map. takes raw means and makes them binary or cut by a single mean threshold
            raw_mean <- raster::weighted.mean(cont.sel.1, w = pond.stats)
            #raw_mean <- raster::mean(cont.sel.1)#el futuro es nuestro
            #if ("raw_mean" %in% which_models) {
                names(raw_mean) <- "raw_mean"#(4)
                final_algo <- raster::addLayer(final_algo, raw_mean)
            #}
            if (any(c("raw_mean_th", "raw_mean_cut") %in% which_models)) {
                        th.mean <- mean(stats.algo[, mean_th_par][sel.index])
                raw_mean_th <- (raw_mean > th.mean)  #(7)
                if ("raw_mean_th" %in% which_models) {
                names(raw_mean_th) <- "raw_mean_th"
                final_algo <- raster::addLayer(final_algo, raw_mean_th)
                }
                if ("raw_mean_cut" %in% which_models) {
                    raw_mean_cut <- raw_mean * raw_mean_th #(9)
                    names(raw_mean_cut) <- "raw_mean_cut"
                    final_algo <- raster::addLayer(final_algo, raw_mean_cut)
                    }
                }
             #second column of the figure. creates binary first -they may have been NOT created in disk but the information to do so is available so instead of running again do_any() we read the raw models and create them here
             if (any(c("bin_mean", "bin_consensus") %in% which_models)) {
                 mod.sel.bin <- cont.sel.1 > (stats.algo[, mean_th_par][sel.index]) #(0)

                if (any(c("bin_mean", "bin_consensus") %in% which_models)) {
                    bin_mean <- raster::weighted.mean(mod.sel.bin, w = pond.stats)  #(5)
                    names(bin_mean) <- "bin_mean"
                    final_algo <- raster::addLayer(final_algo, bin_mean)
                    if ("bin_consensus" %in% which_models) {
                        if (is.null(consensus_level)) {
                            stop("if bin_consensus is selected, consensus_level
                                 must be specified")
                        }
                        bin_consensus <- (bin_mean > consensus_level)  #(8)
                        names(bin_consensus) <- "bin_consensus"
                        final_algo <- raster::addLayer(final_algo, bin_consensus)
                    }
                }
             }

            if (scale_models == TRUE) {
             final_algo <- rescale_layer(final_algo)
            }

            #incerteza #ö está criando esta camada duplicada com cada algoritmo
            if (uncertainty == TRUE) {
                raw_inctz <- raster::calc(cont.sel.1,
                                          fun = function(x) {
                                              max(x) - min(x)
                                              })
                names(raw_inctz) <- "raw_uncertainty"
                final_algo <- raster::addLayer(final_algo, raw_inctz)
                }
            #creation ok
                #message(paste("selected final models for", species_name, algo, "run", run, "DONE"))
                message(paste("selected final models for", species_name, algo, "DONE"))
        }
#################

        if (raster::nlayers(final_algo) != 0) {
            if (uncertainty == TRUE) {
                which_f <- c(which_models, "raw_uncertainty")
                } else {
                    which_f <- which_models
                }
            which_final <- final_algo[[which_f]]

           message(paste("Writing models", algo))
           if (raster::nlayers(which_final) > 1 ) {
           raster::writeRaster(which_final,
                                filename = paste0(final_folder,
                                                  "/", species_name, "_", algo),
                                suffix = "names",
                                bylayer = TRUE,
                                format = "GTiff", ...)
               }
           if (raster::nlayers(which_final) == 1 ) {
           raster::writeRaster(which_final,
                                filename = paste0(final_folder,
                                                  "/", species_name, "_", algo,
                                                  "_", names(which_final)),
                                format = "GTiff", ...)
               }

            if (png_final == TRUE) {
                for (i in 1:raster::nlayers(which_final)) {
                    png(filename = paste0(final_folder, "/",
                                          species_name, "_", algo, "_",
                                          names(which_final)[i], ".png"))
                    raster::plot(which_final[[i]], main = names(which_final)[i])
                    dev.off()
                }
            }

        }

    } #else {
      #  warning(paste("no models were selected for", species_name, algo))
    #}
      #  }
    # creating and writing final_model metadata
    metadata <- data.frame(
      species_name = as.character(species_name),
      algorithms = paste(algorithms, collapse = "-"),
      scale_models = ifelse(scale_models, "yes", "no"),
      consensus_level = ifelse(sum(which_models %in% "bin_consensus" == 1), consensus_level, NA),
      which_models = paste(which_models, collapse = "-"),
      mean_th_par = ifelse(is.null(mean_th_par), "no", mean_th_par),
      uncertainty = ifelse(uncertainty, "yes", "no")
      )
    message("writing metadata")
    write.csv(metadata, file = paste0(final_folder, "/metadata.csv"))

    #writes session info
    write_session_info(final_folder)

    print(paste("DONE", algo, "!"))
    return(stats)
    print(date())
}
