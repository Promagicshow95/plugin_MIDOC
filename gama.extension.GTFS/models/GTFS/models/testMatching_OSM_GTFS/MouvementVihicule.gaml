/**
 * Name: DiagnosticCoherenceRapide
 * Author: Diagnostic allégé GTFS-OSM
 * Description: Version rapide du diagnostic de cohérence
 */

model DiagnosticCoherenceRapide

global {
    // CONFIGURATION FICHIERS
    string results_folder <- "../../results/";
    string stops_folder <- "../../results/stopReseau/";
    
    file data_file <- shape_file("../../includes/shapeFileHanoishp.shp");
    geometry shape <- envelope(data_file);
    
    // VARIABLES DE BASE
    int total_bus_routes <- 0;
    int total_bus_stops <- 0;
    int matched_stops <- 0;
    int unmatched_stops <- 0;
    
    // STRUCTURES
    map<string, bus_stop> stopId_to_agent;
    map<string, bus_route> osmId_to_route;
    
    // VARIABLES DIAGNOSTIC (SIMPLIFIEES)
    int stops_with_missing_routes <- 0;
    int routes_without_stops <- 0;
    int suspicious_distances <- 0;
    
    // PARAMETRES ALLÉGÉS
    int max_route_files <- 3; // Charger seulement 3 fichiers au lieu de 30
    int sample_size <- 1000;  // Échantillon pour tests lourds
    float distance_threshold <- 100.0; // 100m au lieu de 200m

    init {
        write "=== DIAGNOSTIC RAPIDE GTFS-OSM ===";
        
        do load_sample_network;
        do load_gtfs_stops;
        do build_mappings;
        
        // Diagnostics allégés
        do quick_route_coverage;
        do quick_stop_matching;
        do quick_distance_check;
        
        do quick_report;
    }
    
    // CHARGEMENT ÉCHANTILLON DE ROUTES (seulement 3 fichiers)
    action load_sample_network {
        write "\n1. CHARGEMENT ECHANTILLON ROUTES";
        
        int routes_count <- 0;
        
        loop i from: 0 to: max_route_files - 1 {
            string filename <- results_folder + "bus_routes_part" + i + ".shp";
            
            try {
                file shape_file_bus <- shape_file(filename);
                
                create bus_route from: shape_file_bus with: [
                    route_name::string(read("name")),
                    osm_id::string(read("osm_id")),
                    route_type::string(read("route_type"))
                ];
                
                routes_count <- routes_count + length(shape_file_bus);
                write "Fichier " + i + ": " + length(shape_file_bus) + " routes";
                
            } catch {
                write "Fichier " + i + " non trouvé";
            }
        }
        
        // Nettoyer routes sans géométrie
        ask bus_route where (each.shape = nil) {
            do die;
        }
        
        total_bus_routes <- length(bus_route);
        write "TOTAL routes échantillon: " + total_bus_routes;
    }
    
    // CHARGEMENT ARRÊTS (complet car plus léger)
    action load_gtfs_stops {
        write "\n2. CHARGEMENT ARRETS GTFS";
        
        try {
            file shape_file_stops <- shape_file(stops_folder + "gtfs_stops_complete.shp");
            
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
            
            write "Arrêts chargés: " + total_bus_stops + " (matchés: " + matched_stops + ")";
            
        } catch {
            write "ERREUR chargement arrêts";
        }
    }
    
    // MAPPINGS
    action build_mappings {
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
        
        write "Mappings: " + length(stopId_to_agent) + " arrêts, " + length(osmId_to_route) + " routes";
    }
    
    // DIAGNOSTIC 1: COUVERTURE (échantillonné)
    action quick_route_coverage {
        write "\n=== DIAGNOSTIC 1: COUVERTURE ROUTES ===";
        
        routes_without_stops <- 0;
        int checked <- 0;
        
        // Échantillon de routes pour test rapide
        ask min(sample_size, total_bus_routes) among bus_route {
            list<bus_stop> nearby_stops <- bus_stop where (each.closest_route_id = self.osm_id);
            if length(nearby_stops) = 0 {
                routes_without_stops <- routes_without_stops + 1;
            }
            checked <- checked + 1;
        }
        
        float coverage_rate <- (checked - routes_without_stops) / checked * 100;
        write "Routes testées: " + checked;
        write "Routes sans arrêts: " + routes_without_stops;
        write "Taux de couverture: " + round(coverage_rate) + "%";
    }
    
    // DIAGNOSTIC 2: CORRESPONDANCE DES IDs (complet car rapide)
    action quick_stop_matching {
        write "\n=== DIAGNOSTIC 2: CORRESPONDANCE IDS ===";
        
        stops_with_missing_routes <- 0;
        int stops_without_route_id <- 0;
        
        ask bus_stop {
            if closest_route_id = nil or closest_route_id = "" {
                stops_without_route_id <- stops_without_route_id + 1;
            } else if !(osmId_to_route contains_key closest_route_id) {
                stops_with_missing_routes <- stops_with_missing_routes + 1;
            }
        }
        
        write "Arrêts sans route_id: " + stops_without_route_id;
        write "Arrêts avec route_id inexistant: " + stops_with_missing_routes;
        write "Note: test sur échantillon " + max_route_files + "/" + "30 fichiers routes";
    }
    
    // DIAGNOSTIC 3: DISTANCES (échantillonné)
    action quick_distance_check {
        write "\n=== DIAGNOSTIC 3: DISTANCES ===";
        
        list<float> distances <- [];
        suspicious_distances <- 0;
        
        // Échantillon d'arrêts matchés
        list<bus_stop> sample_stops <- min(sample_size, matched_stops) among (bus_stop where (each.is_matched and each.closest_route_dist > 0));
        
        ask sample_stops {
            add closest_route_dist to: distances;
            if closest_route_dist > distance_threshold {
                suspicious_distances <- suspicious_distances + 1;
            }
        }
        
        if length(distances) > 0 {
            float avg_dist <- sum(distances) / length(distances);
            float min_dist <- min(distances);
            float max_dist <- max(distances);
            
            write "Echantillon testé: " + length(distances) + " arrêts";
            write "Distance min: " + round(min_dist) + "m";
            write "Distance max: " + round(max_dist) + "m";
            write "Distance moyenne: " + round(avg_dist) + "m";
            write "Distances suspectes (>" + distance_threshold + "m): " + suspicious_distances;
        }
    }
    
    // RAPPORT RAPIDE
    action quick_report {
        write "\n================================================";
        write "RAPPORT DIAGNOSTIC RAPIDE";
        write "================================================";
        
        // Calculs basiques
        float coverage_score <- routes_without_stops = 0 ? 100.0 : (1 - routes_without_stops / min(sample_size, total_bus_routes)) * 100;
        float matching_score <- (1 - stops_with_missing_routes / total_bus_stops) * 100;
        float distance_score <- suspicious_distances = 0 ? 100.0 : (1 - suspicious_distances / min(sample_size, matched_stops)) * 100;
        
        float global_score <- (coverage_score + matching_score + distance_score) / 3;
        
        write "\nSCORES (sur échantillon):";
        write "-> Couverture routes: " + round(coverage_score) + "%";
        write "-> Correspondance IDs: " + round(matching_score) + "%";
        write "-> Qualité distances: " + round(distance_score) + "%";
        write "-> SCORE GLOBAL: " + round(global_score) + "%";
        
        write "\nDONNEES:";
        write "-> Routes échantillon: " + total_bus_routes + " (sur ~139k total)";
        write "-> Arrêts: " + total_bus_stops + " (" + matched_stops + " matchés)";
        write "-> Fichiers routes testés: " + max_route_files + "/30";
        
        write "\nEVALUATION:";
        if global_score > 85 {
            write "QUALITE BONNE sur l'échantillon testé";
        } else if global_score > 70 {
            write "QUALITE MOYENNE - problèmes mineurs détectés";
        } else {
            write "QUALITE FAIBLE - problèmes majeurs détectés";
        }
        
        if stops_with_missing_routes > total_bus_stops * 0.05 {
            write "ATTENTION: Beaucoup d'arrêts référencent des routes manquantes";
            write "-> Cela peut expliquer la navigation erratique des bus";
        }
        
        write "================================================";
    }
}

// AGENTS SIMPLIFIÉS
species bus_route {
    string route_name;
    string osm_id;
    string route_type;
    
    aspect default {
        if shape != nil {
            // Code couleur simple
            rgb color <- #blue;
            list<bus_stop> stops <- bus_stop where (each.closest_route_id = self.osm_id);
            if length(stops) = 0 {
                color <- #red; // Pas d'arrêts
            } else if length(stops) > 5 {
                color <- #green; // Bien utilisée
            }
            
            draw shape color: color width: 2;
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
        rgb color <- #green; // Par défaut OK
        
        if !is_matched {
            color <- #red;
        } else if closest_route_id = nil or closest_route_id = "" {
            color <- #orange;
        } else if !(osmId_to_route contains_key closest_route_id) {
            color <- #purple; // Route manquante
        } else if closest_route_dist > distance_threshold {
            color <- #yellow; // Trop loin
        }
        
        draw circle(100) color: color;
    }
}

experiment DiagnosticRapide type: gui {
    parameter "Fichiers routes max" var: max_route_files min: 1 max: 10 category: "Performance";
    parameter "Taille échantillon" var: sample_size min: 100 max: 5000 category: "Performance";
    parameter "Seuil distance (m)" var: distance_threshold min: 50.0 max: 300.0 category: "Qualité";
    
    output {
        display "Diagnostic Rapide" background: #white type: 2d {
            species bus_route aspect: default;
            species bus_stop aspect: default;
        }
        
        monitor "Score global %" value: round(((routes_without_stops = 0 ? 100.0 : (1 - routes_without_stops / min(sample_size, total_bus_routes)) * 100) + (1 - stops_with_missing_routes / total_bus_stops) * 100 + (suspicious_distances = 0 ? 100.0 : (1 - suspicious_distances / min(sample_size, matched_stops)) * 100)) / 3);
        monitor "Routes testées" value: min(sample_size, total_bus_routes);
        monitor "Routes sans arrêts" value: routes_without_stops;
        monitor "Arrêts route manquante" value: stops_with_missing_routes;
        monitor "Distances suspectes" value: suspicious_distances;
        monitor "Arrêts matchés" value: matched_stops;
    }
}