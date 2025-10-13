/**
 * Name: CompareBusNetworks
 * Description: Comparaison réseau bus OSM vs GTFS - Analyse de cohérence
 * Date: 2025-10-10
 */

model CompareBusNetworks

global {
    // CONFIGURATION FICHIERS
    string osm_folder <- "../../results1/";
    string gtfs_folder <- "../../results2/";
    string output_folder <- "../../results_comparison/";
    shape_file boundary_shp <- shape_file("../../includes/ShapeFileNantes.shp");
    geometry shape <- envelope(boundary_shp);
    
    // PARAMETRES ANALYSE
    float buffer_tolerance <- 20.0 #m;
    int grid_size <- 500; // Taille cellule en mètres
    float snap_tolerance <- 30.0 #m;
    bool run_routability_tests <- false; // Désactivé par défaut (lourd)
    int sample_size_routability <- 50;
    
    // STATISTIQUES GLOBALES
    int nb_osm_routes <- 0;
    int nb_gtfs_routes <- 0;
    float total_length_osm <- 0.0;
    float total_length_gtfs <- 0.0;
    
    // COVERAGE
    float gtfs_covered_by_osm <- 0.0; // % GTFS avec OSM proche
    float osm_near_gtfs <- 0.0; // % OSM utilisé par GTFS
    
    // INCOHERENCES
    int nb_gtfs_gaps <- 0; // Segments GTFS sans OSM
    int nb_osm_surplus <- 0; // Segments OSM loin de GTFS
    list<geometry> gtfs_gap_segments <- [];
    
    // ROUTABILITE
    graph osm_graph;
    int routable_shapes <- 0;
    int non_routable_shapes <- 0;
    
    init {
        write "\n╔═══════════════════════════════════════╗";
        write "║  COMPARAISON RESEAUX BUS OSM vs GTFS  ║";
        write "╚═══════════════════════════════════════╝\n";
        
        // ETAPE 1: Chargement
        do load_networks;
        
        // ETAPE 2: KPI globaux
        do compute_global_kpis;
        
        // ETAPE 3: Coverage bidirectionnel
        do compute_coverage;
        
        // ETAPE 4: Détection incohérences
        do detect_incoherences;
        
        // ETAPE 5: Heatmap par tuiles
        do create_grid_analysis;
        
        // ETAPE 6: Tests routabilité (optionnel)
        if run_routability_tests {
            do test_routability;
        }
        
        // ETAPE 7: Résumé et export
        do print_summary;
        do export_results;
        
        write "\n═══════════════════════════════════════";
        write "ANALYSE TERMINEE";
        write "═══════════════════════════════════════\n";
    }
    
    // ═══════════════════════════════════════
    // CHARGEMENT RESEAUX
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
        
        // Nettoyer géométries nulles OSM
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
        
        // Nettoyer géométries nulles GTFS
        ask gtfs_route where (each.shape = nil or each.shape.perimeter < 1.0) {
            do die;
        }
        
        nb_gtfs_routes <- length(gtfs_route);
        total_length_gtfs <- sum(gtfs_route collect each.shape.perimeter) / 1000;
        
        write "  ✓ GTFS : " + nb_gtfs_routes + " routes (" + (total_length_gtfs with_precision 1) + " km)";
    }
    
    // ═══════════════════════════════════════
    // KPI GLOBAUX
    // ═══════════════════════════════════════
    
    action compute_global_kpis {
        write "\n► KPI GLOBAUX";
        
        write "  Nb routes OSM  : " + nb_osm_routes;
        write "  Nb routes GTFS : " + nb_gtfs_routes;
        write "  Longueur OSM   : " + (total_length_osm with_precision 1) + " km";
        write "  Longueur GTFS  : " + (total_length_gtfs with_precision 1) + " km";
        
        float ratio <- total_length_osm > 0 ? total_length_gtfs / total_length_osm : 0.0;
        write "  Ratio GTFS/OSM : " + (ratio with_precision 2);
        
        if total_length_osm < total_length_gtfs {
            write "  ⚠️  ALERTE: OSM plus court que GTFS (données incomplètes?)";
        }
        
        // Emprises
        geometry osm_envelope <- union(osm_route collect each.shape).envelope;
        geometry gtfs_envelope <- union(gtfs_route collect each.shape).envelope;
        
        write "  Emprise OSM  : " + int(osm_envelope.width) + " x " + int(osm_envelope.height) + " m";
        write "  Emprise GTFS : " + int(gtfs_envelope.width) + " x " + int(gtfs_envelope.height) + " m";
    }
    
    // ═══════════════════════════════════════
    // COVERAGE BIDIRECTIONNEL
    // ═══════════════════════════════════════
    
    action compute_coverage {
        write "\n► ANALYSE COVERAGE (buffer=" + buffer_tolerance + "m)";
        
        // 1. GTFS couvert par OSM (méthode simplifiée et robuste)
        float gtfs_covered_length <- 0.0;
        int gtfs_processed <- 0;
        int gtfs_with_osm <- 0;
        
        loop gtfs over: gtfs_route {
            gtfs_processed <- gtfs_processed + 1;
            
            // Trouver OSM proches
            list<osm_route> nearby_osm <- osm_route where (each.shape distance_to gtfs.shape < buffer_tolerance);
            
            if !empty(nearby_osm) {
                gtfs_with_osm <- gtfs_with_osm + 1;
                
                // Méthode simplifiée : si OSM proche, considérer route couverte
                gtfs_covered_length <- gtfs_covered_length + gtfs.shape.perimeter;
            }
            
            // Debug tous les 50 items
            if gtfs_processed mod 50 = 0 {
                write "  ... traité " + gtfs_processed + "/" + nb_gtfs_routes + " routes GTFS";
            }
        }
        
        gtfs_covered_by_osm <- total_length_gtfs > 0 ? 
            (100.0 * gtfs_covered_length / (total_length_gtfs * 1000)) : 0.0;
        
        write "  Routes GTFS avec OSM proche : " + gtfs_with_osm + "/" + nb_gtfs_routes;
        write "  GTFS couvert par OSM : " + (gtfs_covered_by_osm with_precision 1) + "%";
        
        if gtfs_covered_by_osm < 80 {
            write "  🔴 PROBLEME: Coverage < 80% (OSM incomplet ou buffer trop petit)";
            write "  💡 Essayez d'augmenter buffer_tolerance à 50m ou 100m";
        } else if gtfs_covered_by_osm < 90 {
            write "  🟠 ATTENTION: Coverage 80-90% (à vérifier)";
        } else {
            write "  🟢 OK: Coverage > 90%";
        }
        
        // 2. OSM proche de GTFS (méthode simplifiée)
        write "\n  Calcul coverage OSM→GTFS...";
        
        float osm_near_length <- 0.0;
        int osm_processed <- 0;
        int osm_near_count <- 0;
        
        loop osm over: osm_route {
            osm_processed <- osm_processed + 1;
            
            // Trouver GTFS proches
            bool has_nearby_gtfs <- false;
            loop gtfs over: gtfs_route {
                if osm.shape distance_to gtfs.shape < buffer_tolerance {
                    has_nearby_gtfs <- true;
                    break;
                }
            }
            
            if has_nearby_gtfs {
                osm_near_count <- osm_near_count + 1;
                osm_near_length <- osm_near_length + osm.shape.perimeter;
            }
            
            // Debug tous les 10000 items
            if osm_processed mod 10000 = 0 {
                write "  ... traité " + osm_processed + "/" + nb_osm_routes + " routes OSM";
            }
        }
        
        osm_near_gtfs <- total_length_osm > 0 ? 
            (100.0 * osm_near_length / (total_length_osm * 1000)) : 0.0;
        
        write "  Routes OSM proches GTFS : " + osm_near_count + "/" + nb_osm_routes;
        write "  OSM utilisé par GTFS : " + (osm_near_gtfs with_precision 1) + "%";
        write "  OSM non utilisé     : " + ((100 - osm_near_gtfs) with_precision 1) + "%";
    }
    
    // ═══════════════════════════════════════
    // DETECTION INCOHERENCES
    // ═══════════════════════════════════════
    
    action detect_incoherences {
        write "\n► DETECTION INCOHERENCES";
        
        // Trous GTFS (sans OSM proche)
        loop gtfs over: gtfs_route {
            geometry buffer_gtfs <- gtfs.shape buffer buffer_tolerance;
            list<osm_route> nearby_osm <- osm_route overlapping buffer_gtfs;
            
            if empty(nearby_osm) {
                nb_gtfs_gaps <- nb_gtfs_gaps + 1;
                gtfs_gap_segments << gtfs.shape;
                
                create incoherence_marker {
                    location <- gtfs.shape.location;
                    incoherence_type <- "GTFS_NO_OSM";
                    length_m <- gtfs.shape.perimeter;
                    shape <- gtfs.shape;
                }
            } else {
                // Vérifier couverture partielle
                geometry osm_union <- union(nearby_osm collect each.shape);
                geometry covered <- gtfs.shape inter osm_union;
                
                float coverage_ratio <- covered != nil ? 
                    covered.perimeter / gtfs.shape.perimeter : 0.0;
                
                if coverage_ratio < 0.5 {
                    nb_gtfs_gaps <- nb_gtfs_gaps + 1;
                    
                    create incoherence_marker {
                        location <- gtfs.shape.location;
                        incoherence_type <- "GTFS_PARTIAL";
                        length_m <- gtfs.shape.perimeter;
                        coverage_pct <- coverage_ratio * 100;
                        shape <- gtfs.shape;
                    }
                }
            }
        }
        
        write "  Segments GTFS sans OSM : " + nb_gtfs_gaps + " (" + 
              ((100.0 * nb_gtfs_gaps / nb_gtfs_routes) with_precision 1) + "%)";
        
        // Surplus OSM (loin de GTFS)
        geometry gtfs_union <- union(gtfs_route collect each.shape);
        geometry gtfs_buffer <- gtfs_union buffer (buffer_tolerance * 2);
        
        loop osm over: osm_route {
            if not (osm.shape intersects gtfs_buffer) {
                nb_osm_surplus <- nb_osm_surplus + 1;
            }
        }
        
        write "  Segments OSM hors GTFS : " + nb_osm_surplus + " (" + 
              ((100.0 * nb_osm_surplus / nb_osm_routes) with_precision 1) + "%)";
        
        if nb_gtfs_gaps > nb_gtfs_routes * 0.2 {
            write "  🔴 ALERTE: > 20% des routes GTFS sans OSM";
        }
    }
    
    // ═══════════════════════════════════════
    // HEATMAP PAR TUILES
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
                float len_intersect <- 0.0;
                
                // GTFS dans cellule
                loop gtfs over: gtfs_route where (each.shape intersects cell_geom) {
                    geometry part <- gtfs.shape inter cell_geom;
                    if part != nil {
                        len_gtfs <- len_gtfs + part.perimeter;
                    }
                }
                
                // OSM dans cellule
                loop osm over: osm_route where (each.shape intersects cell_geom) {
                    geometry part <- osm.shape inter cell_geom;
                    if part != nil {
                        len_osm <- len_osm + part.perimeter;
                    }
                }
                
                // Score cellule
                if len_gtfs > 10 or len_osm > 10 {
                    float score <- len_gtfs > 0 ? (len_osm / len_gtfs) : 0.0;
                    score <- min(1.0, score); // Cap à 100%
                    
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
        
        write "  Cellules BONNES   : " + good_cells + " (vert)";
        write "  Cellules MOYENNES : " + medium_cells + " (orange)";
        write "  Cellules MAUVAISES: " + bad_cells + " (rouge)";
    }
    
    // ═══════════════════════════════════════
    // TESTS ROUTABILITE
    // ═══════════════════════════════════════
    
    action test_routability {
        write "\n► TESTS ROUTABILITE (échantillon=" + sample_size_routability + ")";
        
        // Construire graphe OSM
        list<geometry> osm_edges <- osm_route collect each.shape;
        if !empty(osm_edges) {
            osm_graph <- as_edge_graph(osm_edges);
        }
        
        if osm_graph = nil {
            write "  ✗ Impossible de créer le graphe OSM";
            return;
        }
        
        // Tester échantillon GTFS
        list<gtfs_route> sample <- sample_size_routability among gtfs_route;
        
        loop gtfs over: sample {
            list<point> points <- gtfs.shape.points;
            if length(points) >= 2 {
                point start_point <- first(points);
                point end_point <- last(points);
                
                // Snap aux noeuds OSM
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
        
        if routable_pct < 70 {
            write "  🔴 PROBLEME: < 70% routables";
        } else if routable_pct < 90 {
            write "  🟠 ATTENTION: 70-90% routables";
        } else {
            write "  🟢 OK: > 90% routables";
        }
    }
    
    // ═══════════════════════════════════════
    // RESUME
    // ═══════════════════════════════════════
    
    action print_summary {
        write "\n╔═══════════════════════════════════════╗";
        write "║           RESUME ANALYSE              ║";
        write "╚═══════════════════════════════════════╝";
        
        write "\n📊 STATISTIQUES GLOBALES:";
        write "  OSM  : " + nb_osm_routes + " routes, " + (total_length_osm with_precision 1) + " km";
        write "  GTFS : " + nb_gtfs_routes + " routes, " + (total_length_gtfs with_precision 1) + " km";
        
        write "\n📈 COVERAGE:";
        write "  GTFS couvert par OSM : " + (gtfs_covered_by_osm with_precision 1) + "%";
        write "  OSM utilisé par GTFS : " + (osm_near_gtfs with_precision 1) + "%";
        
        write "\n⚠️  INCOHERENCES:";
        write "  Segments GTFS sans OSM : " + nb_gtfs_gaps;
        write "  Segments OSM hors GTFS : " + nb_osm_surplus;
        
        write "\n🗺️  QUALITE SPATIALE:";
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
                write "  Routes routables : " + ((100.0 * routable_shapes / total) with_precision 1) + "%";
            }
        }
        
        write "\n💡 INTERPRETATION:";
        if gtfs_covered_by_osm > 90 and (routable_shapes + non_routable_shapes = 0 or 
            routable_shapes / (routable_shapes + non_routable_shapes) > 0.9) {
            write "  ✅ RESEAUX COHERENTS - Navigation fiable possible";
        } else if gtfs_covered_by_osm > 80 {
            write "  ⚠️  COHERENCE ACCEPTABLE - Quelques ajustements recommandés";
        } else {
            write "  ❌ INCOHERENCES IMPORTANTES - Vérifier données sources";
        }
    }
    
    // ═══════════════════════════════════════
    // EXPORT RESULTATS
    // ═══════════════════════════════════════
    
    action export_results {
        write "\n► EXPORT RESULTATS...";
        
        try {
            // Export grille
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
            
            // Export incohérences
            if length(incoherence_marker) > 0 {
                save incoherence_marker to: output_folder + "incoherences.shp" format: "shp"
                    attributes: [
                        "type"::incoherence_type,
                        "length_m"::length_m,
                        "cover_pct"::coverage_pct
                    ];
                write "  ✓ incoherences.shp";
            }
            
            write "  Fichiers dans: " + output_folder;
            
        } catch {
            write "  ✗ Erreur export (vérifier que le dossier existe)";
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
    float coverage_pct;
    
    aspect base {
        rgb marker_color <- incoherence_type = "GTFS_NO_OSM" ? #red :
                           (incoherence_type = "GTFS_PARTIAL" ? #orange : #yellow);
        draw shape color: marker_color width: 4;
        draw circle(50) color: marker_color at: location;
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
}

// ═══════════════════════════════════════
// EXPERIMENT
// ═══════════════════════════════════════

experiment CompareNetworks type: gui {
    parameter "Buffer tolérance (m)" var: buffer_tolerance min: 10.0 max: 50.0;
    parameter "Taille grille (m)" var: grid_size min: 200 max: 1000;
    parameter "Tests routabilité" var: run_routability_tests;
    parameter "Échantillon routabilité" var: sample_size_routability min: 10 max: 200;
    
    output {
        display "Comparaison Réseaux" background: #white type: 2d {
            species osm_route aspect: base transparency: 0.5;
            species gtfs_route aspect: base;
            species incoherence_marker aspect: base;
        }
        
        display "Heatmap Cohérence" background: #white type: 2d {
            species grid_cell aspect: base transparency: 0.3;
            species gtfs_route aspect: base transparency: 0.7;
            
            graphics "legende" {
                draw "Cohérence:" at: {shape.location.x - shape.width/2 + 100, 
                                       shape.location.y + shape.height/2 - 100} 
                     color: #black font: font("Arial", 14, #bold);
                draw rectangle(30, 30) at: {shape.location.x - shape.width/2 + 100, 
                                            shape.location.y + shape.height/2 - 150} 
                     color: #green border: #black;
                draw "> 85%" at: {shape.location.x - shape.width/2 + 150, 
                                  shape.location.y + shape.height/2 - 150} 
                     color: #black;
                draw rectangle(30, 30) at: {shape.location.x - shape.width/2 + 100, 
                                            shape.location.y + shape.height/2 - 200} 
                     color: #orange border: #black;
                draw "60-85%" at: {shape.location.x - shape.width/2 + 150, 
                                   shape.location.y + shape.height/2 - 200} 
                     color: #black;
                draw rectangle(30, 30) at: {shape.location.x - shape.width/2 + 100, 
                                            shape.location.y + shape.height/2 - 250} 
                     color: #red border: #black;
                draw "< 60%" at: {shape.location.x - shape.width/2 + 150, 
                                  shape.location.y + shape.height/2 - 250} 
                     color: #black;
            }
        }
        
        monitor "OSM routes" value: nb_osm_routes;
        monitor "GTFS routes" value: nb_gtfs_routes;
        monitor "Coverage GTFS→OSM" value: string(gtfs_covered_by_osm with_precision 1) + "%";
        monitor "Coverage OSM→GTFS" value: string(osm_near_gtfs with_precision 1) + "%";
        monitor "Incohérences GTFS" value: nb_gtfs_gaps;
        monitor "Surplus OSM" value: nb_osm_surplus;
        monitor "Cellules analysées" value: length(grid_cell);
        monitor "Zones problématiques" value: length(grid_cell where (each.quality = "BAD"));
    }
}