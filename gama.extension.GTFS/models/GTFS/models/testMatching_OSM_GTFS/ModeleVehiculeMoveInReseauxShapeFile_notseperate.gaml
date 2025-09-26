/**
 * Name: DiagnosticCoherenceReseauBus
 * Author: Diagnostic de cohérence GTFS-OSM
 * Description: Vérifications de cohérence entre arrêts GTFS et routes OSM
 */

model DiagnosticCoherenceReseauBus

global {
    // CONFIGURATION FICHIERS
    string results_folder <- "../../results/";
    string stops_folder <- "../../results/stopReseau/";
    
    file data_file <- shape_file("../../includes/shapeFileHanoishp.shp");
    geometry shape <- envelope(data_file);
    
    // VARIABLES STATISTIQUES DE BASE
    int total_bus_routes <- 0;
    int total_bus_stops <- 0;
    int matched_stops <- 0;
    int unmatched_stops <- 0;
    
    // STRUCTURES BASIQUES
    map<string, bus_stop> stopId_to_agent;
    map<string, bus_route> osmId_to_route;
    
    // === VARIABLES DIAGNOSTIC ===
    int stops_with_missing_routes <- 0;
    int routes_without_stops <- 0;
    int stops_far_from_routes <- 0;
    int routes_without_geometry <- 0;
    int orphaned_stop_route_ids <- 0;
    
    list<string> missing_route_ids <- [];
    list<string> suspicious_distances <- [];
    float max_distance_threshold <- 200.0; // 200m max entre arrêt et route
    
    // STATISTIQUES DE DISTANCE
    float min_distance <- 999999.0;
    float max_distance <- 0.0;
    float avg_distance <- 0.0;
    list<float> all_distances <- [];

    init {
        write "=== DIAGNOSTIC COHÉRENCE GTFS-OSM ===";
        
        do load_bus_network;
        do load_gtfs_stops;
        do build_basic_mappings;
        
        // === DIAGNOSTICS PRINCIPAUX ===
        do diagnostic_route_coverage;
        do diagnostic_stop_route_matching;
        do diagnostic_distance_quality;
        do diagnostic_geometric_validity;
        
        // === RAPPORT FINAL ===
        do generate_diagnostic_report;
    }
    
    // === DIAGNOSTIC 1: COUVERTURE DES ROUTES ===
    action diagnostic_route_coverage {
        write "\n=== DIAGNOSTIC 1: COUVERTURE DES ROUTES ===";
        
        // Quelles routes OSM n'ont aucun arrêt GTFS ?
        routes_without_stops <- 0;
        ask bus_route {
            list<bus_stop> nearby_stops <- bus_stop where (each.closest_route_id = self.osm_id);
            if length(nearby_stops) = 0 {
                routes_without_stops <- routes_without_stops + 1;
                if routes_without_stops <= 5 { // Afficher seulement les 5 premiers
                    write "⚠️ Route sans arrêts: " + osm_id + " (" + route_name + ")";
                }
            }
        }
        
        write "→ Routes sans arrêts GTFS: " + routes_without_stops + "/" + total_bus_routes;
        write "→ Pourcentage routes utilisées: " + round((1 - routes_without_stops/total_bus_routes) * 100) + "%";
    }
    
    // === DIAGNOSTIC 2: CORRESPONDANCE STOP-ROUTE ===
    action diagnostic_stop_route_matching {
        write "\n=== DIAGNOSTIC 2: CORRESPONDANCE STOP-ROUTE ===";
        
        stops_with_missing_routes <- 0;
        orphaned_stop_route_ids <- 0;
        missing_route_ids <- [];
        
        ask bus_stop {
            if closest_route_id != nil and closest_route_id != "" {
                // Vérifier si la route référencée existe vraiment
                if !(osmId_to_route contains_key closest_route_id) {
                    stops_with_missing_routes <- stops_with_missing_routes + 1;
                    if !(missing_route_ids contains closest_route_id) {
                        add closest_route_id to: missing_route_ids;
                    }
                }
            } else {
                // Arrêt sans route assignée
                orphaned_stop_route_ids <- orphaned_stop_route_ids + 1;
            }
        }
        
        write "→ Arrêts avec route manquante: " + stops_with_missing_routes + "/" + total_bus_stops;
        write "→ Arrêts sans route assignée: " + orphaned_stop_route_ids + "/" + total_bus_stops;
        write "→ IDs de routes manquantes uniques: " + length(missing_route_ids);
        
        if length(missing_route_ids) > 0 and length(missing_route_ids) <= 10 {
            write "→ Exemples routes manquantes: " + missing_route_ids;
        }
    }
    
    // === DIAGNOSTIC 3: QUALITÉ DES DISTANCES ===
    action diagnostic_distance_quality {
        write "\n=== DIAGNOSTIC 3: QUALITÉ DES DISTANCES ===";
        
        stops_far_from_routes <- 0;
        all_distances <- [];
        suspicious_distances <- [];
        
        ask bus_stop {
            if is_matched and closest_route_dist > 0 {
                add closest_route_dist to: all_distances;
                
                // Collecter les distances suspectes
                if closest_route_dist > max_distance_threshold {
                    stops_far_from_routes <- stops_far_from_routes + 1;
                    if length(suspicious_distances) < 10 {
                        add (stopId + ": " + round(closest_route_dist) + "m") to: suspicious_distances;
                    }
                }
            }
        }
        
        if length(all_distances) > 0 {
            min_distance <- min(all_distances);
            max_distance <- max(all_distances);
            avg_distance <- sum(all_distances) / length(all_distances);
            
            write "→ Distance min: " + round(min_distance * 10)/10 + "m";
            write "→ Distance max: " + round(max_distance * 10)/10 + "m";
            write "→ Distance moyenne: " + round(avg_distance * 10)/10 + "m";
            write "→ Arrêts trop éloignés (>" + max_distance_threshold + "m): " + stops_far_from_routes;
            
            if length(suspicious_distances) > 0 {
                write "→ Exemples distances suspectes:";
                loop dist over: suspicious_distances {
                    write "   • " + dist;
                }
            }
        }
    }
    
    // === DIAGNOSTIC 4: VALIDITÉ GÉOMÉTRIQUE ===
    action diagnostic_geometric_validity {
        write "\n=== DIAGNOSTIC 4: VALIDITÉ GÉOMÉTRIQUE ===";
        
        routes_without_geometry <- 0;
        int stops_without_geometry <- 0;
        
        ask bus_route {
            if shape = nil {
                routes_without_geometry <- routes_without_geometry + 1;
            }
        }
        
        ask bus_stop {
            if location = nil {
                stops_without_geometry <- stops_without_geometry + 1;
            }
        }
        
        write "→ Routes sans géométrie: " + routes_without_geometry + "/" + total_bus_routes;
        write "→ Arrêts sans position: " + stops_without_geometry + "/" + total_bus_stops;
        
        // Test de connectivité basique (échantillon)
        int connectivity_tests <- min(10, length(bus_route));
        int disconnected_routes <- 0;
        
        ask connectivity_tests among bus_route {
            if shape != nil {
                // Tester si la route a des intersections avec d'autres routes
                list<bus_route> nearby_routes <- bus_route where (each != self and each.shape != nil);
                list<bus_route> intersecting <- nearby_routes where (each.shape intersects self.shape);
                
                if length(intersecting) = 0 {
                    disconnected_routes <- disconnected_routes + 1;
                }
            }
        }
        
        write "→ Routes potentiellement isolées (échantillon): " + disconnected_routes + "/" + connectivity_tests;
    }
    
    // === RAPPORT FINAL ===
    action generate_diagnostic_report {
        string separator <- "==================================================";
        write "\n" + separator;
        write "RAPPORT DIAGNOSTIC FINAL";
        write separator;
        
        // Score global de cohérence
        float coverage_score <- (1 - routes_without_stops/total_bus_routes) * 100;
        float matching_score <- (1 - stops_with_missing_routes/total_bus_stops) * 100;
        float distance_score <- (1 - stops_far_from_routes/matched_stops) * 100;
        float geometry_score <- (1 - routes_without_geometry/total_bus_routes) * 100;
        
        float overall_score <- (coverage_score + matching_score + distance_score + geometry_score) / 4;
        
        write "\nSCORES DE COHERENCE:";
        write "-> Couverture routes: " + round(coverage_score * 10)/10 + "%";
        write "-> Correspondance IDs: " + round(matching_score * 10)/10 + "%";
        write "-> Qualite distances: " + round(distance_score * 10)/10 + "%";
        write "-> Validite geometrique: " + round(geometry_score * 10)/10 + "%";
        write "-> SCORE GLOBAL: " + round(overall_score * 10)/10 + "%";
        
        // Recommandations
        write "\nRECOMMANDATIONS:";
        
        if routes_without_stops > total_bus_routes * 0.3 {
            write "CRITIQUE: " + round(routes_without_stops/total_bus_routes*100) + "% des routes n'ont pas d'arrets";
            write "   -> Verifier l'algorithme de matching arrets-routes";
        }
        
        if stops_with_missing_routes > total_bus_stops * 0.1 {
            write "PROBLEME: " + round(stops_with_missing_routes/total_bus_stops*100) + "% arrets referencent des routes inexistantes";
            write "   -> Synchroniser les donnees GTFS et OSM";
        }
        
        if avg_distance > 50 {
            write "ATTENTION: Distance moyenne arret-route = " + round(avg_distance) + "m";
            write "   -> Ameliorer la precision du matching geospatial";
        }
        
        if overall_score > 80 {
            write "QUALITE BONNE: Les donnees sont coherentes";
        } else if overall_score > 60 {
            write "QUALITE MOYENNE: Ameliorations necessaires";
        } else {
            write "QUALITE FAIBLE: Revision majeure requise";
        }
        
        write "\nTaille echantillon: " + total_bus_routes + " routes, " + total_bus_stops + " arrets";
        write separator;
    }
    
    // === CHARGEMENT DES DONNÉES ===
    action load_bus_network {
        write "\n1. CHARGEMENT RÉSEAU BUS";
        
        int bus_routes_count <- 0;
        int i <- 0;
        bool continue_loading <- true;
        
        loop while: continue_loading and i < 30 {
            string filename <- results_folder + "bus_routes_part" + i + ".shp";
            
            try {
                file shape_file_bus <- shape_file(filename);
                
                create bus_route from: shape_file_bus with: [
                    route_name::string(read("name")),
                    osm_id::string(read("osm_id")),
                    route_type::string(read("route_type")),
                    highway_type::string(read("highway")),
                    length_meters::float(read("length_m"))
                ];
                
                bus_routes_count <- bus_routes_count + length(shape_file_bus);
                i <- i + 1;
                
            } catch {
                continue_loading <- false;
            }
        }
        
        total_bus_routes <- bus_routes_count;
        write "Routes chargées : " + bus_routes_count;
        
        ask bus_route where (each.shape = nil) {
            do die;
        }
        
        total_bus_routes <- length(bus_route);
        write "Routes avec géométrie valide : " + total_bus_routes;
    }
    
    action load_gtfs_stops {
        write "\n2. CHARGEMENT ARRÊTS GTFS";
        
        string stops_filename <- stops_folder + "gtfs_stops_complete.shp";
        
        try {
            file shape_file_stops <- shape_file(stops_filename);
            
            create bus_stop from: shape_file_stops with: [
                stopId::string(read("stopId")),
                stop_name::string(read("name")),
                closest_route_id::string(read("closest_id")),
                closest_route_dist::float(read("distance")),
                is_matched_str::string(read("matched"))
            ];
            
            total_bus_stops <- length(shape_file_stops);
            
            ask bus_stop {
                is_matched <- (is_matched_str = "TRUE");
                
                if is_matched {
                    matched_stops <- matched_stops + 1;
                } else {
                    unmatched_stops <- unmatched_stops + 1;
                }
            }
            
            write "Arrêts chargés : " + total_bus_stops;
            write "  - Matchés: " + matched_stops;
            write "  - Non matchés: " + unmatched_stops;
            
        } catch {
            write "ERREUR : Impossible de charger " + stops_filename;
        }
    }
    
    action build_basic_mappings {
        write "\n3. CONSTRUCTION MAPPINGS";
        
        stopId_to_agent <- map<string, bus_stop>([]);
        ask bus_stop {
            if stopId != nil and stopId != "" {
                stopId_to_agent[stopId] <- self;
            }
        }
        
        osmId_to_route <- map<string, bus_route>([]);
        ask bus_route {
            if osm_id != nil and osm_id != "" {
                osmId_to_route[osm_id] <- self;
            }
        }
        
        write "Mappings créés :";
        write "  - stopId -> agent : " + length(stopId_to_agent);
        write "  - osmId -> route : " + length(osmId_to_route);
    }
}

// AGENTS SIMPLIFIÉS POUR LE DIAGNOSTIC
species bus_route {
    string route_name;
    string osm_id;
    string route_type;
    string highway_type;
    float length_meters;
    
    aspect default {
        if shape != nil {
            rgb route_color <- #gray;
            
            // Identifier les routes problématiques visuellement
            list<bus_stop> nearby_stops <- bus_stop where (each.closest_route_id = self.osm_id);
            if length(nearby_stops) = 0 {
                route_color <- #red; // Route sans arrêts
            } else if length(nearby_stops) > 10 {
                route_color <- #green; // Route bien utilisée
            } else {
                route_color <- #blue; // Route normale
            }
            
            draw shape color: route_color width: 2;
        }
    }
}

species bus_stop {
    string stopId;
    string stop_name;
    string closest_route_id;
    float closest_route_dist;
    bool is_matched;
    string is_matched_str;
    
    aspect default {
        rgb stop_color <- #gray;
        
        // Coloration selon les problèmes détectés
        if !is_matched {
            stop_color <- #red; // Non matché
        } else if closest_route_id = nil or closest_route_id = "" {
            stop_color <- #orange; // Pas de route assignée
        } else if !(osmId_to_route contains_key closest_route_id) {
            stop_color <- #purple; // Route référencée inexistante
        } else if closest_route_dist > max_distance_threshold {
            stop_color <- #yellow; // Trop loin de la route
        } else {
            stop_color <- #green; // OK
        }
        
        draw circle(100) color: stop_color;
    }
}

experiment DiagnosticCoherence type: gui {
    output {
        display "Diagnostic Cohérence" background: #white type: 2d {
            species bus_route aspect: default;
            species bus_stop aspect: default;
        }
        
        monitor "Score global %" value: round(((1 - routes_without_stops/total_bus_routes) + (1 - stops_with_missing_routes/total_bus_stops) + (1 - stops_far_from_routes/matched_stops) + (1 - routes_without_geometry/total_bus_routes)) / 4 * 100);
        monitor "Routes sans arrêts" value: routes_without_stops;
        monitor "Arrêts sans route" value: stops_with_missing_routes;
        monitor "Distance moy. (m)" value: round(avg_distance * 10)/10;
        monitor "Arrêts trop loin" value: stops_far_from_routes;
        monitor "Routes invalides" value: routes_without_geometry;
        
        monitor "Total routes" value: total_bus_routes;
        monitor "Total arrêts" value: total_bus_stops;
        monitor "Arrêts matchés" value: matched_stops;
        monitor "IDs routes manquantes" value: length(missing_route_ids);
    }
}