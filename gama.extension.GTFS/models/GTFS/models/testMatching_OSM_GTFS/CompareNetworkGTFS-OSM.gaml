model CompareGTFS_OSM

global {
    // === FICHIERS ===
    gtfs_file gtfs_f <- gtfs_file("../../includes/nantes_gtfs");
    shape_file boundary_shp <- shape_file("../../includes/ShapeFileNantes.shp");
    string osm_folder <- "../../results1/";
    
    geometry shape <- envelope(boundary_shp);
    
    // === PARAMÈTRES ===
    float TOLERANCE_M <- 20.0;  // Tolérance pour considérer qu'une route est couverte
    bool strict_departures <- false;
    
    // === RÉSEAUX ===
    geometry osm_union;         // Union de toutes les routes OSM
    geometry osm_mask;          // Buffer des routes OSM
    
    // === STATISTIQUES ===
    int total_gtfs_shapes <- 0;
    int fully_covered <- 0;
    int partially_covered <- 0;
    int not_covered <- 0;
    float global_coverage_ratio <- 0.0;
    
    init {
        write "=== COMPARAISON GTFS vs OSM ===\n";
        
        // ÉTAPE 1: Charger GTFS
        do load_gtfs_network;
        
        // ÉTAPE 2: Charger OSM
        do load_osm_network;
        
        // ÉTAPE 3: Préparer la comparaison
        do prepare_osm_mask;
        
        // ÉTAPE 4: Détecter les manques
        do detect_missing_segments;
        
        // ÉTAPE 5: Calculer les statistiques
        do compute_statistics;
        
        write "\n=== RÉSULTATS ===";
        write "Routes GTFS analysées: " + total_gtfs_shapes;
        write "Complètement couvertes: " + fully_covered + " (" + (fully_covered * 100.0 / total_gtfs_shapes) with_precision 1 + "%)";
        write "Partiellement couvertes: " + partially_covered + " (" + (partially_covered * 100.0 / total_gtfs_shapes) with_precision 1 + "%)";
        write "Non couvertes: " + not_covered + " (" + (not_covered * 100.0 / total_gtfs_shapes) with_precision 1 + "%)";
        write "Couverture globale: " + (global_coverage_ratio with_precision 1) + "%";
    }
    
    // ========== ÉTAPE 1: CHARGER GTFS ==========
    action load_gtfs_network {
        write "📍 Chargement réseau GTFS...";
        
        create bus_stop from: gtfs_f;
        create gtfs_shape from: gtfs_f;
        
        write "  Arrêts: " + length(bus_stop);
        write "  Shapes: " + length(gtfs_shape);
        
        // Filtrer pour garder seulement les bus
        list<string> bus_shape_ids <- [];
        
        ask (bus_stop where (each.routeType = 3 and each.tripShapeMap != nil)) {
            loop sid over: values(tripShapeMap) {
                if (sid != nil and !(bus_shape_ids contains sid)) {
                    bus_shape_ids <- bus_shape_ids + sid;
                }
            }
        }
        
        write "  ShapeIds de bus: " + length(bus_shape_ids);
        
        // Marquer et compter les shapes de bus
        ask gtfs_shape {
            is_bus <- bus_shape_ids contains shapeId;
        }
        
        total_gtfs_shapes <- length(gtfs_shape where each.is_bus);
        write "✅ Shapes de bus GTFS: " + total_gtfs_shapes;
    }
    
    // ========== ÉTAPE 2: CHARGER OSM ==========
    action load_osm_network {
        write "\n🗺️ Chargement réseau OSM...";
        
        int i <- 0;
        bool continue_loading <- true;
        
        loop while: continue_loading {
            string filepath <- osm_folder + "bus_routes_part" + i + ".shp";
            
            try {
                shape_file shp <- shape_file(filepath);
                create osm_route from: shp;
                write "  ✅ Part" + i + ": " + length(shp.contents) + " routes";
                i <- i + 1;
            } catch {
                if (i = 0) {
                    write "  ❌ Aucun fichier trouvé";
                }
                continue_loading <- false;
            }
        }
        
        write "✅ Routes OSM chargées: " + length(osm_route);
    }
    
    // ========== ÉTAPE 3: PRÉPARER MASQUE OSM ==========
    action prepare_osm_mask {
        write "\n🔧 Préparation du masque OSM (tolérance: " + TOLERANCE_M + "m)...";
        
        // Union de toutes les géométries OSM
        list<geometry> osm_geoms <- osm_route collect each.shape;
        
        if (length(osm_geoms) > 0) {
            osm_union <- union(osm_geoms);
            osm_mask <- buffer(osm_union, TOLERANCE_M);
            write "✅ Masque OSM créé";
        } else {
            write "❌ Pas de géométries OSM";
        }
    }
    
    // ========== ÉTAPE 4: DÉTECTER LES MANQUES ==========
    action detect_missing_segments {
        write "\n🔍 Détection des segments manquants...";
        
        if (osm_mask = nil) {
            write "❌ Masque OSM non disponible";
            return;
        }
        
        int processed <- 0;
        
        ask (gtfs_shape where each.is_bus) {
            if (shape != nil) {
                // Calculer la partie non couverte
                geometry missing <- shape - osm_mask;
                
                if (missing != nil and !empty(missing.points)) {
                    // Calculer le ratio de couverture
                    float total_length <- shape.perimeter;
                    float missing_length <- missing.perimeter;
                    coverage_ratio <- total_length > 0 ? ((total_length - missing_length) / total_length) * 100.0 : 0.0;
                    
                    // Créer un agent pour visualiser le segment manquant
                    if (coverage_ratio < 100.0) {
                        create missing_segment {
                            shape <- missing;
                            parent_shape_id <- myself.shapeId;
                            missing_length_m <- missing_length;
                        }
                    }
                } else {
                    coverage_ratio <- 100.0;
                }
                
                processed <- processed + 1;
                
                if (processed mod 50 = 0) {
                    write "  Analysé: " + processed + "/" + total_gtfs_shapes;
                }
            }
        }
        
        write "✅ Segments manquants détectés: " + length(missing_segment);
    }
    
    // ========== ÉTAPE 5: STATISTIQUES ==========
    action compute_statistics {
        write "\n📊 Calcul des statistiques...";
        
        float total_coverage <- 0.0;
        
        ask (gtfs_shape where each.is_bus) {
            if (coverage_ratio >= 99.0) {
                fully_covered <- fully_covered + 1;
            } else if (coverage_ratio > 50.0) {
                partially_covered <- partially_covered + 1;
            } else {
                not_covered <- not_covered + 1;
            }
            
            total_coverage <- total_coverage + coverage_ratio;
        }
        
        global_coverage_ratio <- total_gtfs_shapes > 0 ? (total_coverage / total_gtfs_shapes) : 0.0;
        
        // Identifier les pires cas
        list<gtfs_shape> worst_cases <- (gtfs_shape where each.is_bus) sort_by each.coverage_ratio;
        
        write "\n⚠️ Pires cas de couverture:";
        loop i from: 0 to: min(4, length(worst_cases) - 1) {
            gtfs_shape s <- worst_cases[i];
            write "  - Shape " + s.shapeId + ": " + (s.coverage_ratio with_precision 1) + "% couvert";
        }
    }
}

// ========== ESPÈCES ==========

// Arrêts GTFS
species bus_stop skills: [TransportStopSkill] {
    aspect base {
        rgb color <- (routeType = 3) ? #red : #lightblue;
        draw circle(30) color: color;
    }
}

// Shapes GTFS
species gtfs_shape skills: [TransportShapeSkill] {
    bool is_bus <- false;
    float coverage_ratio <- 0.0;
    
    aspect default {
        if (is_bus and shape != nil) {
            // Couleur selon le taux de couverture
            rgb color <- coverage_ratio >= 99.0 ? #blue : 
                        (coverage_ratio >= 75.0 ? #orange : #red);
            draw shape color: color width: 2;
        }
    }
    
    aspect coverage_heatmap {
        if (is_bus and shape != nil) {
            // Dégradé de couleur: vert (100%) -> rouge (0%)
            int r <- int(255 * (1 - coverage_ratio / 100.0));
            int g <- int(255 * (coverage_ratio / 100.0));
            rgb color <- rgb(r, g, 0);
            draw shape color: color width: 3;
        }
    }
}

// Routes OSM
species osm_route {
    aspect default {
        draw shape color: #green width: 1.5;
    }
    
    aspect faint {
        draw shape color: #lightgreen width: 1;
    }
}

// Segments manquants
species missing_segment {
    string parent_shape_id;
    float missing_length_m;
    
    aspect default {
        draw shape color: #red width: 4;
    }
    
    aspect highlight {
        draw shape color: #red width: 5;
    }
}

// ========== EXPÉRIENCE ==========
experiment CompareNetworks type: gui {
    output {
        // Display 1: Vue d'ensemble
        display "Overview" type: 2d background: #white {
            species osm_route aspect: faint;
            species gtfs_shape aspect: default;
            species missing_segment aspect: default;
            
            overlay position: {10, 10} size: {300 #px, 180 #px} background: #white transparency: 0.1 border: #black {
                draw "GTFS vs OSM" at: {10 #px, 20 #px} font: font("Arial", 14, #bold);
                draw "Routes GTFS: " + total_gtfs_shapes at: {15 #px, 45 #px};
                draw "Routes OSM: " + length(osm_route) at: {15 #px, 65 #px};
                draw "Segments manquants: " + length(missing_segment) at: {15 #px, 85 #px};
                draw "Couverture: " + (global_coverage_ratio with_precision 1) + "%" at: {15 #px, 105 #px};
                draw "Tolérance: " + TOLERANCE_M + "m" at: {15 #px, 125 #px} color: #gray;
            }
        }
        
        // Display 2: Carte de chaleur de couverture
        display "Coverage Heatmap" type: 2d background: #white {
            species osm_route aspect: faint transparency: 0.5;
            species gtfs_shape aspect: coverage_heatmap;
            
            overlay position: {10, 10} size: {200 #px, 100 #px} background: #white transparency: 0.1 {
                draw "Légende:" at: {10 #px, 20 #px} font: font("Arial", 12, #bold);
                draw rectangle(15, 15) at: {20 #px, 40 #px} color: #green;
                draw "100% couvert" at: {40 #px, 43 #px};
                draw rectangle(15, 15) at: {20 #px, 60 #px} color: #orange;
                draw "75-99% couvert" at: {40 #px, 63 #px};
                draw rectangle(15, 15) at: {20 #px, 80 #px} color: #red;
                draw "<75% couvert" at: {40 #px, 83 #px};
            }
        }
        
        // Display 3: Seulement les manques
        display "Missing Segments Only" type: 2d background: #white {
            species osm_route aspect: faint transparency: 0.7;
            species missing_segment aspect: highlight;
            
            overlay position: {10, 10} size: {250 #px, 80 #px} background: #white transparency: 0.1 {
                draw "Segments GTFS manquants" at: {10 #px, 20 #px} font: font("Arial", 12, #bold);
                draw "Total: " + length(missing_segment) + " segments" at: {15 #px, 45 #px};
                float total_missing <- sum(missing_segment collect each.missing_length_m);
                draw "Longueur: " + (total_missing / 1000.0) with_precision 2 + " km" at: {15 #px, 65 #px};
            }
        }
        
        // Monitors
        monitor "Couverture globale (%)" value: global_coverage_ratio with_precision 1;
        monitor "Complètement couverts" value: fully_covered;
        monitor "Partiellement couverts" value: partially_covered;
        monitor "Non couverts" value: not_covered;
        monitor "Segments manquants" value: length(missing_segment);
    }
}