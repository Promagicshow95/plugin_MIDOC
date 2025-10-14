/**
 * Name: CompareBusNetworks_Fixed
 * Description: Comparaison réseau bus OSM vs GTFS - CORRECTION LOGIQUE
 * Date: 2025-10-15
 */

model CompareBusNetworks_Fixed

global {
    // CONFIGURATION FICHIERS
    string osm_folder <- "../../results1/";
    string gtfs_folder <- "../../results2/";
    string output_folder <- "../../results_comparison/";
    shape_file boundary_shp <- shape_file("../../includes/ShapeFileNantes.shp");
    geometry shape <- envelope(boundary_shp);
    
    // ✅ PARAMÈTRES ANALYSE (augmentés selon recommandations)
    float buffer_tolerance <- 30.0 #m; // ✅ Augmenté de 20 à 30m
    int grid_size <- 500;
    float snap_tolerance <- 30.0 #m;
    bool run_routability_tests <- false;
    int sample_size_routability <- 50;
    
    // ✅ NOUVEAU : Résolution échantillonnage
    float segment_sample_distance <- 10.0 #m; // Échantillonner tous les 10m
    
    // STATISTIQUES GLOBALES
    int nb_osm_routes <- 0;
    int nb_gtfs_routes <- 0;
    float total_length_osm <- 0.0;
    float total_length_gtfs <- 0.0;
    
    // ✅ COVERAGE CORRIGÉ (par longueur réelle, pas par route entière)
    float gtfs_covered_by_osm <- 0.0;
    float osm_near_gtfs <- 0.0;
    
    // ✅ INCOHÉRENCES CORRIGÉES (par segments, pas par intersection ligne-ligne)
    int nb_gtfs_gap_segments <- 0;
    float gtfs_gap_length <- 0.0;
    int nb_osm_surplus_segments <- 0;
    float osm_surplus_length <- 0.0;
    
    // ROUTABILITE
    graph osm_graph;
    int routable_shapes <- 0;
    int non_routable_shapes <- 0;
    
    init {
        write "\n╔═══════════════════════════════════════╗";
        write "║  COMPARAISON CORRIGÉE OSM vs GTFS     ║";
        write "╚═══════════════════════════════════════╝\n";
        
        do load_networks;
        do compute_global_kpis;
        do compute_coverage_fixed; // ✅ Nouvelle méthode
        do detect_incoherences_fixed; // ✅ Nouvelle méthode
        do create_grid_analysis;
        
        if run_routability_tests {
            do test_routability;
        }
        
        do print_summary_fixed; // ✅ Résumé corrigé
        do export_results;
        
        write "\n═══════════════════════════════════════";
        write "ANALYSE TERMINEE";
        write "═══════════════════════════════════════\n";
    }
    
    // ═══════════════════════════════════════
    // CHARGEMENT (inchangé)
    // ═══════════════════════════════════════
    
    action load_networks {
        write "► CHARGEMENT RESEAUX...";
        
        // OSM
        int i <- 0;
        loop while: i < 20 {
            string filename <- osm_folder + "bus_routes_part" + i + ".shp";
            try {
                file osm_shp <- shape_file(filename);
                create osm_route from: osm_shp;
                i <- i + 1;
            } catch {
                i <- 20;
            }
        }
        
        ask osm_route where (each.shape = nil or each.shape.perimeter < 1.0) {
            do die;
        }
        
        nb_osm_routes <- length(osm_route);
        total_length_osm <- sum(osm_route collect each.shape.perimeter) / 1000;
        
        write "  ✓ OSM : " + nb_osm_routes + " routes (" + (total_length_osm with_precision 1) + " km)";
        
        // GTFS
        i <- 0;
        loop while: i < 20 {
            string filename <- gtfs_folder + "bus_shapes_part" + i + ".shp";
            try {
                file gtfs_shp <- shape_file(filename);
                create gtfs_route from: gtfs_shp with: [
                    shape_id :: int(read("shape_id"))
                ];
                i <- i + 1;
            } catch {
                i <- 20;
            }
        }
        
        ask gtfs_route where (each.shape = nil or each.shape.perimeter < 1.0) {
            do die;
        }
        
        nb_gtfs_routes <- length(gtfs_route);
        total_length_gtfs <- sum(gtfs_route collect each.shape.perimeter) / 1000;
        
        write "  ✓ GTFS : " + nb_gtfs_routes + " routes (" + (total_length_gtfs with_precision 1) + " km)";
    }
    
    action compute_global_kpis {
        write "\n► KPI GLOBAUX";
        write "  Nb routes OSM  : " + nb_osm_routes;
        write "  Nb routes GTFS : " + nb_gtfs_routes;
        write "  Longueur OSM   : " + (total_length_osm with_precision 1) + " km";
        write "  Longueur GTFS  : " + (total_length_gtfs with_precision 1) + " km";
        
        float ratio <- total_length_osm > 0 ? total_length_gtfs / total_length_osm : 0.0;
        write "  Ratio GTFS/OSM : " + (ratio with_precision 2);
    }
    
    // ═══════════════════════════════════════
    // ✅ COVERAGE CORRIGÉ PAR SEGMENTS
    // ═══════════════════════════════════════
    
    action compute_coverage_fixed {
        write "\n► ANALYSE COVERAGE CORRIGÉE (buffer=" + buffer_tolerance + "m)";
        write "  Méthode: échantillonnage par segments tous les " + segment_sample_distance + "m";
        
        // ✅ 1. GTFS → OSM : Coverage par longueur réelle
        write "\n  [1/2] Calcul GTFS couvert par OSM...";
        
        geometry osm_union <- union(osm_route collect each.shape);
        
        float covered_len <- 0.0;
        float total_len <- 0.0;
        int gtfs_processed <- 0;
        
        loop gtfs over: gtfs_route {
            gtfs_processed <- gtfs_processed + 1;
            
            list<point> pts <- gtfs.shape.points;
            
            // ✅ Échantillonner les segments
            loop i from: 0 to: length(pts) - 2 {
                point a <- pts[i];
                point b <- pts[i + 1];
                float seg_len <- a distance_to b;
                
                if seg_len <= 0.0 {
                    continue;
                }
                
                total_len <- total_len + seg_len;
                
                // ✅ Créer segment et tester distance
                geometry seg <- polyline([a, b]);
                float d <- seg distance_to osm_union;
                
                if d <= buffer_tolerance {
                    covered_len <- covered_len + seg_len;
                }
            }
            
            if gtfs_processed mod 50 = 0 {
                write "    ... traité " + gtfs_processed + "/" + nb_gtfs_routes + " routes GTFS";
            }
        }
        
        gtfs_covered_by_osm <- total_len > 0.0 ? 100.0 * covered_len / total_len : 0.0;
        
        write "  ✓ Longueur GTFS totale    : " + (total_len with_precision 0) + " m";
        write "  ✓ Longueur GTFS couverte  : " + (covered_len with_precision 0) + " m";
        write "  ✓ GTFS couvert par OSM    : " + (gtfs_covered_by_osm with_precision 1) + "%";
        
        // ✅ 2. OSM → GTFS : Coverage inverse
        write "\n  [2/2] Calcul OSM utilisé par GTFS...";
        
        geometry gtfs_union <- union(gtfs_route collect each.shape);
        
        float osm_near_len <- 0.0;
        float osm_total_len <- 0.0;
        int osm_processed <- 0;
        
        loop osm over: osm_route {
            osm_processed <- osm_processed + 1;
            
            list<point> pts <- osm.shape.points;
            
            loop i from: 0 to: length(pts) - 2 {
                point a <- pts[i];
                point b <- pts[i + 1];
                float seg_len <- a distance_to b;
                
                if seg_len <= 0.0 {
                    continue;
                }
                
                osm_total_len <- osm_total_len + seg_len;
                
                geometry seg <- polyline([a, b]);
                float d <- seg distance_to gtfs_union;
                
                if d <= buffer_tolerance {
                    osm_near_len <- osm_near_len + seg_len;
                }
            }
            
            if osm_processed mod 5000 = 0 {
                write "    ... traité " + osm_processed + "/" + nb_osm_routes + " routes OSM";
            }
        }
        
        osm_near_gtfs <- osm_total_len > 0.0 ? 100.0 * osm_near_len / osm_total_len : 0.0;
        
        write "  ✓ Longueur OSM totale     : " + (osm_total_len with_precision 0) + " m";
        write "  ✓ Longueur OSM proche GTFS: " + (osm_near_len with_precision 0) + " m";
        write "  ✓ OSM utilisé par GTFS    : " + (osm_near_gtfs with_precision 1) + "%";
        write "  ✓ OSM non utilisé         : " + ((100 - osm_near_gtfs) with_precision 1) + "%";
        
        // ✅ Interprétation
        write "\n  💡 INTERPRÉTATION COVERAGE:";
        if gtfs_covered_by_osm >= 90 {
            write "    🟢 Excellent (≥90%) : OSM couvre bien le réseau GTFS";
        } else if gtfs_covered_by_osm >= 80 {
            write "    🟠 Acceptable (80-90%) : Quelques trous OSM";
        } else if gtfs_covered_by_osm >= 70 {
            write "    🟠 Moyen (70-80%) : Trous significatifs OSM";
        } else {
            write "    🔴 Insuffisant (<70%) : OSM largement incomplet";
            write "       → Vérifier extraction OSM ou augmenter buffer_tolerance";
        }
    }
    
    // ═══════════════════════════════════════
    // ✅ DÉTECTION INCOHÉRENCES PAR BUFFERS
    // ═══════════════════════════════════════
    
    action detect_incoherences_fixed {
        write "\n► DETECTION INCOHERENCES (méthode buffers)";
        
        geometry osm_union <- union(osm_route collect each.shape);
        geometry gtfs_union <- union(gtfs_route collect each.shape);
        
        // ✅ 1. Segments GTFS sans OSM proche (méthode segment par segment)
        write "  [1/2] Analyse segments GTFS...";
        
        int gtfs_processed <- 0;
        
        loop gtfs over: gtfs_route {
            gtfs_processed <- gtfs_processed + 1;
            
            list<point> pts <- gtfs.shape.points;
            bool this_route_has_gap <- false;
            
            loop i from: 0 to: length(pts) - 2 {
                point a <- pts[i];
                point b <- pts[i + 1];
                geometry seg <- polyline([a, b]);
                float seg_len <- a distance_to b;
                
                if seg_len <= 0.0 {
                    continue;
                }
                
                // ✅ Tester distance segment → OSM
                float dist_to_osm <- seg distance_to osm_union;
                
                if dist_to_osm > buffer_tolerance {
                    this_route_has_gap <- true;
                    gtfs_gap_length <- gtfs_gap_length + seg_len;
                    
                    // ✅ Créer marqueur pour ce segment manquant
                    create incoherence_marker {
                        location <- seg.location;
                        incoherence_type <- "GTFS_NO_OSM";
                        length_m <- seg_len;
                        distance_to_network <- dist_to_osm;
                        shape <- seg;
                    }
                }
            }
            
            if this_route_has_gap {
                nb_gtfs_gap_segments <- nb_gtfs_gap_segments + 1;
            }
            
            if gtfs_processed mod 50 = 0 {
                write "    ... traité " + gtfs_processed + "/" + nb_gtfs_routes + " routes GTFS";
            }
        }
        
        float gtfs_gap_pct <- nb_gtfs_routes > 0 ? 
            100.0 * nb_gtfs_gap_segments / nb_gtfs_routes : 0.0;
        
        write "  ✓ Routes GTFS avec manque OSM : " + nb_gtfs_gap_segments + "/" + nb_gtfs_routes + 
              " (" + (gtfs_gap_pct with_precision 1) + "%)";
        write "  ✓ Longueur segments manquants : " + (gtfs_gap_length with_precision 0) + " m " +
              "(" + ((gtfs_gap_length / (total_length_gtfs * 1000) * 100) with_precision 1) + "%)";
        
        // ✅ 2. Segments OSM loin de GTFS (surplus)
        write "\n  [2/2] Analyse segments OSM...";
        
        int osm_processed <- 0;
        
        loop osm over: osm_route {
            osm_processed <- osm_processed + 1;
            
            list<point> pts <- osm.shape.points;
            bool this_route_is_surplus <- false;
            
            loop i from: 0 to: length(pts) - 2 {
                point a <- pts[i];
                point b <- pts[i + 1];
                geometry seg <- polyline([a, b]);
                float seg_len <- a distance_to b;
                
                if seg_len <= 0.0 {
                    continue;
                }
                
                float dist_to_gtfs <- seg distance_to gtfs_union;
                
                if dist_to_gtfs > buffer_tolerance * 2 { // ✅ Double buffer pour surplus
                    this_route_is_surplus <- true;
                    osm_surplus_length <- osm_surplus_length + seg_len;
                }
            }
            
            if this_route_is_surplus {
                nb_osm_surplus_segments <- nb_osm_surplus_segments + 1;
            }
            
            if osm_processed mod 5000 = 0 {
                write "    ... traité " + osm_processed + "/" + nb_osm_routes + " routes OSM";
            }
        }
        
        float osm_surplus_pct <- nb_osm_routes > 0 ? 
            100.0 * nb_osm_surplus_segments / nb_osm_routes : 0.0;
        
        write "  ✓ Routes OSM hors GTFS : " + nb_osm_surplus_segments + "/" + nb_osm_routes + 
              " (" + (osm_surplus_pct with_precision 1) + "%)";
        write "  ✓ Longueur surplus OSM : " + (osm_surplus_length with_precision 0) + " m";
        
        // ✅ Interprétation
        write "\n  💡 INTERPRÉTATION INCOHÉRENCES:";
        if gtfs_gap_pct <= 10 {
            write "    🟢 Très bon (≤10%) : Peu de manques OSM";
        } else if gtfs_gap_pct <= 20 {
            write "    🟠 Acceptable (10-20%) : Quelques trous localisés";
        } else if gtfs_gap_pct <= 30 {
            write "    🟠 Moyen (20-30%) : Trous significatifs";
        } else {
            write "    🔴 Problématique (>30%) : Nombreux trous OSM";
            write "       → OSM incomplet ou buffer_tolerance trop strict";
        }
    }
    
    // ═══════════════════════════════════════
    // GRILLE (inchangé, déjà correct)
    // ═══════════════════════════════════════
    
    action create_grid_analysis {
        write "\n► ANALYSE PAR GRILLE (" + grid_size + "m)";
        
        int grid_width <- int(shape.width / grid_size) + 1;
        int grid_height <- int(shape.height / grid_size) + 1;
        
        loop x from: 0 to: grid_width - 1 {
            loop y from: 0 to: grid_height - 1 {
                point cell_origin <- shape.location + {x * grid_size - shape.width/2, 
                                                       y * grid_size - shape.height/2};
                geometry cell_geom <- rectangle(grid_size, grid_size) at_location cell_origin;
                
                float len_gtfs <- 0.0;
                float len_osm <- 0.0;
                
                loop gtfs over: gtfs_route where (each.shape intersects cell_geom) {
                    geometry part <- gtfs.shape inter cell_geom;
                    if part != nil {
                        len_gtfs <- len_gtfs + part.perimeter;
                    }
                }
                
                loop osm over: osm_route where (each.shape intersects cell_geom) {
                    geometry part <- osm.shape inter cell_geom;
                    if part != nil {
                        len_osm <- len_osm + part.perimeter;
                    }
                }
                
                if len_gtfs > 10 or len_osm > 10 {
                    float score <- len_gtfs > 0 ? (len_osm / len_gtfs) : 0.0;
                    score <- min(1.0, score);
                    
                    create grid_cell {
                        shape <- cell_geom;
                        gtfs_length <- len_gtfs;
                        osm_length <- len_osm;
                        coherence_score <- score;
                        
                        if score > 0.85 {
                            color <- #green;
                            quality <- "GOOD";
                        } else if score > 0.6 {
                            color <- #orange;
                            quality <- "MEDIUM";
                        } else {
                            color <- #red;
                            quality <- "BAD";
                        }
                    }
                }
            }
        }
        
        int good_cells <- length(grid_cell where (each.quality = "GOOD"));
        int medium_cells <- length(grid_cell where (each.quality = "MEDIUM"));
        int bad_cells <- length(grid_cell where (each.quality = "BAD"));
        
        write "  Cellules BONNES   : " + good_cells;
        write "  Cellules MOYENNES : " + medium_cells;
        write "  Cellules MAUVAISES: " + bad_cells;
    }
    
    // ═══════════════════════════════════════
    // ROUTABILITÉ (inchangé)
    // ═══════════════════════════════════════
    
    action test_routability {
        write "\n► TESTS ROUTABILITE (échantillon=" + sample_size_routability + ")";
        
        list<geometry> osm_edges <- osm_route collect each.shape;
        if !empty(osm_edges) {
            osm_graph <- as_edge_graph(osm_edges);
        }
        
        if osm_graph = nil {
            write "  ✗ Impossible de créer le graphe OSM";
            return;
        }
        
        list<gtfs_route> sample <- sample_size_routability among gtfs_route;
        
        loop gtfs over: sample {
            list<point> points <- gtfs.shape.points;
            if length(points) >= 2 {
                point start_point <- first(points);
                point end_point <- last(points);
                
                point start_snap <- osm_graph.vertices closest_to start_point;
                point end_snap <- osm_graph.vertices closest_to end_point;
                
                if start_snap != nil and end_snap != nil {
                    float dist_start <- start_point distance_to start_snap;
                    float dist_end <- end_point distance_to end_snap;
                    
                    if dist_start < snap_tolerance and dist_end < snap_tolerance {
                        path test_path <- path_between(osm_graph, start_snap, end_snap);
                        
                        if test_path != nil {
                            routable_shapes <- routable_shapes + 1;
                        } else {
                            non_routable_shapes <- non_routable_shapes + 1;
                            
                            create incoherence_marker {
                                location <- gtfs.shape.location;
                                incoherence_type <- "NOT_ROUTABLE";
                                shape <- gtfs.shape;
                            }
                        }
                    } else {
                        non_routable_shapes <- non_routable_shapes + 1;
                    }
                } else {
                    non_routable_shapes <- non_routable_shapes + 1;
                }
            }
        }
        
        int total_tested <- routable_shapes + non_routable_shapes;
        float routable_pct <- total_tested > 0 ? 
            (100.0 * routable_shapes / total_tested) : 0.0;
        
        write "  Routes routables : " + routable_shapes + "/" + total_tested + 
              " (" + (routable_pct with_precision 1) + "%)";
    }
    
    // ═══════════════════════════════════════
    // ✅ RÉSUMÉ CORRIGÉ
    // ═══════════════════════════════════════
    
    action print_summary_fixed {
        write "\n╔═══════════════════════════════════════╗";
        write "║         RESUME ANALYSE CORRIGÉE       ║";
        write "╚═══════════════════════════════════════╝";
        
        write "\n📊 STATISTIQUES:";
        write "  OSM  : " + nb_osm_routes + " routes, " + (total_length_osm with_precision 1) + " km";
        write "  GTFS : " + nb_gtfs_routes + " routes, " + (total_length_gtfs with_precision 1) + " km";
        
        write "\n📈 COVERAGE (par longueur réelle):";
        write "  GTFS couvert par OSM : " + (gtfs_covered_by_osm with_precision 1) + "%";
        write "  OSM utilisé par GTFS : " + (osm_near_gtfs with_precision 1) + "%";
        
        write "\n⚠️  INCOHÉRENCES (segments manquants):";
        float gtfs_gap_pct <- nb_gtfs_routes > 0 ? 
            100.0 * nb_gtfs_gap_segments / nb_gtfs_routes : 0.0;
        write "  Routes GTFS avec trous : " + nb_gtfs_gap_segments + "/" + nb_gtfs_routes + 
              " (" + (gtfs_gap_pct with_precision 1) + "%)";
        write "  Longueur manquante    : " + (gtfs_gap_length / 1000 with_precision 2) + " km";
        
        write "\n🗺️  QUALITÉ SPATIALE:";
        int good <- length(grid_cell where (each.quality = "GOOD"));
        int medium <- length(grid_cell where (each.quality = "MEDIUM"));
        int bad <- length(grid_cell where (each.quality = "BAD"));
        int total_cells <- good + medium + bad;
        
        if total_cells > 0 {
            write "  Zones bonnes   : " + ((100.0 * good / total_cells) with_precision 1) + "%";
            write "  Zones moyennes : " + ((100.0 * medium / total_cells) with_precision 1) + "%";
            write "  Zones mauvaises: " + ((100.0 * bad / total_cells) with_precision 1) + "%";
        }
        
        if run_routability_tests {
            write "\n🛣️  ROUTABILITE:";
            int total <- routable_shapes + non_routable_shapes;
            if total > 0 {
                float routable_pct <- 100.0 * routable_shapes / total;
                write "  Routes routables : " + (routable_pct with_precision 1) + "%";
            }
        }
        
        // ✅ CONCLUSION CORRIGÉE (logique cohérente)
        write "\n💡 CONCLUSION FINALE:";
        
        float gtfs_gap_route_pct <- nb_gtfs_routes > 0 ? 
            100.0 * nb_gtfs_gap_segments / nb_gtfs_routes : 0.0;
        
        int total_routability <- routable_shapes + non_routable_shapes;
        float routability_pct <- total_routability > 0 ? 
            100.0 * routable_shapes / total_routability : 100.0;
        
        // ✅ Décision basée sur TOUTES les métriques
        if gtfs_covered_by_osm >= 90 and gtfs_gap_route_pct <= 10 and 
           (total_routability = 0 or routability_pct >= 90) {
            write "  ✅ RESEAUX COHERENTS";
            write "     → Navigation fiable possible";
            write "     → Données prêtes pour simulation";
        } else if gtfs_covered_by_osm >= 80 and gtfs_gap_route_pct <= 20 {
            write "  ⚠️  COHERENCE ACCEPTABLE";
            write "     → Quelques trous OSM localisés";
            write "     → Vérifier zones rouges dans heatmap";
            write "     → Envisager graphe hybride OSM+GTFS";
        } else if gtfs_covered_by_osm >= 70 {
            write "  🟠 COHERENCE MOYENNE";
            write "     → Trous OSM significatifs";
            write "     → SOLUTION: Utiliser graphe hybride OSM+GTFS shapes";
            write "     → OU augmenter buffer_tolerance à 50-100m";
        } else {
            write "  🔴 INCOHERENCES IMPORTANTES";
            write "     → OSM largement incomplet pour le réseau GTFS";
            write "     → CAUSES POSSIBLES:";
            write "       • Extraction OSM trop restrictive (types de routes)";
            write "       • Zone géographique mal couverte dans OSM";
            write "       • Décalage spatial entre OSM et GTFS";
            write "     → SOLUTIONS:";
            write "       • Réextraire OSM avec plus de types de routes";
            write "       • Utiliser shapes GTFS comme réseau principal";
            write "       • Augmenter buffer_tolerance pour diagnostic";
        }
        
        // ✅ Recommandations spécifiques
        write "\n🔧 RECOMMANDATIONS:";
        if gtfs_gap_route_pct > 20 {
            write "  → Utiliser action create_hybrid_graph (OSM + GTFS shapes)";
        }
        if gtfs_covered_by_osm < 80 {
            write "  → Augmenter buffer_tolerance à 50m pour re-tester";
        }
        if length(incoherence_marker) > 100 {
            write "  → Exporter incoherences.shp et analyser dans QGIS";
        }
    }
    
    // ═══════════════════════════════════════
    // EXPORT (inchangé)
    // ═══════════════════════════════════════
    
    action export_results {
        write "\n► EXPORT RESULTATS...";
        
        try {
            if length(grid_cell) > 0 {
                save grid_cell to: output_folder + "coherence_grid.shp" format: "shp"
                    attributes: [
                        "gtfs_len"::gtfs_length,
                        "osm_len"::osm_length,
                        "score"::coherence_score,
                        "quality"::quality
                    ];
                write "  ✓ coherence_grid.shp";
            }
            
            if length(incoherence_marker) > 0 {
                save incoherence_marker to: output_folder + "incoherences.shp" format: "shp"
                    attributes: [
                        "type"::incoherence_type,
                        "length_m"::length_m,
                        "dist_to_net"::distance_to_network
                    ];
                write "  ✓ incoherences.shp (" + length(incoherence_marker) + " segments)";
            }
            
            write "  Fichiers dans: " + output_folder;
            
        } catch {
            write "  ✗ Erreur export";
        }
    }
}

// ═══════════════════════════════════════
// SPECIES
// ═══════════════════════════════════════

species osm_route {
    aspect base {
        draw shape color: #lightgray width: 1;
    }
}

species gtfs_route {
    int shape_id;
    
    aspect base {
        draw shape color: #blue width: 2;
    }
}

species incoherence_marker {
    string incoherence_type;
    float length_m;
    float distance_to_network; // ✅ NOUVEAU
    
    aspect base {
        rgb marker_color <- incoherence_type = "GTFS_NO_OSM" ? #red :
                           (incoherence_type = "NOT_ROUTABLE" ? #yellow : #orange);
        draw shape color: marker_color width: 4;
        draw circle(30) color: marker_color at: location;
    }
}

species grid_cell {
    float gtfs_length;
    float osm_length;
    float coherence_score;
    string quality;
    rgb color;
    
    aspect base {
   
        draw shape color: color border: #black;
    }
    

    aspect transparent {
        draw shape color: rgb(color, 0.3) border: #black; // 0.3 = 30% opacité
    }
}

// ═══════════════════════════════════════
// EXPERIMENT
// ═══════════════════════════════════════

experiment CompareNetworks_Fixed type: gui {
    parameter "Buffer tolérance (m)" var: buffer_tolerance min: 10.0 max: 100.0;
    parameter "Échantillonnage (m)" var: segment_sample_distance min: 5.0 max: 50.0;
    parameter "Taille grille (m)" var: grid_size min: 200 max: 1000;
    parameter "Tests routabilité" var: run_routability_tests;
    
    output {
        display "Réseaux + Incohérences" background: #white type: 2d {
            species osm_route aspect: base;
            species gtfs_route aspect: base;
            species incoherence_marker aspect: base;
        }
        
        display "Heatmap Cohérence" background: #white type: 2d {
            species grid_cell aspect: base transparency: 0.3;
            species gtfs_route aspect: base transparency: 0.7;
        }
        
        // ✅ MONITORS CORRIGÉS
        monitor "OSM routes" value: nb_osm_routes;
        monitor "GTFS routes" value: nb_gtfs_routes;
        monitor "Coverage GTFS (%)" value: (gtfs_covered_by_osm with_precision 1);
        monitor "OSM utilisé (%)" value: (osm_near_gtfs with_precision 1);
        monitor "Routes avec trous" value: string(nb_gtfs_gap_segments) + "/" + string(nb_gtfs_routes);
        monitor "Longueur manquante (km)" value: (gtfs_gap_length / 1000 with_precision 2);
        monitor "Segments incohérents" value: length(incoherence_marker);
        
        // ✅ BONUS : Monitors supplémentaires utiles
        monitor "% routes avec trous" value: nb_gtfs_routes > 0 ? 
            ((100.0 * nb_gtfs_gap_segments / nb_gtfs_routes) with_precision 1) : 0.0;
        monitor "Cellules analysées" value: length(grid_cell);
        monitor "Cellules problématiques" value: length(grid_cell where (each.quality = "BAD"));
    }
}