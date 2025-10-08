/**
 * Name: GTFS_Graph_Matching_Complete
 * Description: Chargement graphe depuis shapefile + Matching stops GTFS + Simulation véhicule ROBUSTE
 * Tags: GTFS, graph, matching, snapping, zones, vehicle, robust
 * Date: 2025-10-02
 */

model GTFS_Graph_Matching_Complete

global {
    // --- FICHIERS ---
    string results_folder <- "../../results/";
    gtfs_file gtfs_f <- gtfs_file("../../includes/hanoi_gtfs_pm");
    file data_file <- shape_file("../../includes/shapeFileHanoishp.shp");
    geometry shape <- envelope(data_file);
    
    // --- PARAMETRES MATCHING ---
    int grid_size <- 300;
    list<float> search_radii <- [50.0, 100.0, 200.0];
    int batch_size <- 500;
    
    // --- PARAMETRES SIMULATION ---
    float dwell_time <- 30.0 #s;  // Temps d'arrêt par défaut
    float max_speed <- 50.0 #km/#h;  // Vitesse maximum (bus urbain)
    
    // --- GRAPHE ---
    graph road_graph;
    
    // --- STATISTIQUES ---
    int total_stops <- 0;
    int snapped_stops <- 0;
    int warning_stops <- 0;
    int failed_stops <- 0;
    
    // --- STRUCTURES ---
    map<string, bus_stop> stopId_to_agent <- [];
    list<pair<int,int>> neighbors <- [
        {0,0}, {-1,0}, {1,0}, {0,-1}, {0,1},
        {-1,-1}, {-1,1}, {1,-1}, {1,1}
    ];

    init {
        write "=== MATCHING GTFS + GRAPH ===\n";
        
        // 1. Charger graphe depuis shapefile
        do load_graph_from_shapefile;
        
        // 2. Charger stops GTFS
        do load_gtfs_stops;
        
        // 3. Assignation zones spatiales
        do assign_zones;
        
        // 4. Matching spatial par batch
        do snap_stops_with_zones;
        
        // 5. Construire mappings finaux
        do build_final_mappings;
        
        // 6. Indexer stops sur graphe
        do index_stops_on_graph;
        
        // 7. Créer véhicule pour trip spécifique
        do create_specific_bus_robust;
        
        // 8. Rapport
        do final_report;
    }
    
    // CHARGEMENT GRAPHE DEPUIS SHAPEFILE
    action load_graph_from_shapefile {
        write "1. CHARGEMENT GRAPHE";
        
        file edges_shp <- shape_file(results_folder + "graph_edges.shp");
        
        create edge_feature from: edges_shp with: [
            edge_id :: int(read("edge_id")),
            from_id :: int(read("from_id")),
            to_id :: int(read("to_id")),
            length_m :: float(read("length_m"))
        ];
        
        write "Aretes chargees : " + length(edge_feature);
        
        // Créer le graphe
        road_graph <- as_edge_graph(edge_feature);
        
        if road_graph = nil {
            write "ERREUR: Impossible de creer le graphe";
        } else {
            write "Graphe cree avec succes";
        }
    }
    
    // CHARGEMENT STOPS GTFS
    action load_gtfs_stops {
        write "\n2. CHARGEMENT STOPS GTFS";
        
        create bus_stop from: gtfs_f;
        
        total_stops <- length(bus_stop);
        
        write "Stops charges : " + total_stops;
        
        // Stats par type
        map<int, int> stops_per_type <- [];
        ask bus_stop {
            if not (stops_per_type contains_key routeType) {
                stops_per_type[routeType] <- 0;
            }
            stops_per_type[routeType] <- stops_per_type[routeType] + 1;
        }
        
        write "Types de transport :";
        loop route_type over: stops_per_type.keys {
            string type_name <- route_type = 0 ? "Tram" : 
                               (route_type = 1 ? "Metro" : 
                               (route_type = 2 ? "Train" : 
                               (route_type = 3 ? "Bus" : "Autre")));
            write "  " + type_name + " : " + stops_per_type[route_type];
        }
    }
    
    // ASSIGNATION ZONES SPATIALES
    action assign_zones {
        write "\n3. ASSIGNATION ZONES SPATIALES";
        
        // Zones pour stops
        ask bus_stop {
            zone_id <- (int(location.x / grid_size) * 100000) + int(location.y / grid_size);
        }
        
        // Zones pour edges
        ask edge_feature {
            point centroid <- shape.location;
            zone_id <- (int(centroid.x / grid_size) * 100000) + int(centroid.y / grid_size);
        }
        
        write "Zones assignees (grid " + grid_size + "m)";
    }
    
    // SNAPPING AVEC OPTIMISATION PAR ZONES
    action snap_stops_with_zones {
        write "\n4. SNAPPING SPATIAL PAR BATCH";
        
        int current <- 0;
        int processed <- 0;
        
        loop while: current < total_stops {
            int max_idx <- min(current + batch_size - 1, total_stops - 1);
            list<bus_stop> batch <- bus_stop where (each.index >= current and each.index <= max_idx);
            
            loop s over: batch {
                do process_stop_snapping(s);
                processed <- processed + 1;
            }
            
            if processed mod 1000 = 0 {
                write "  Traitement : " + processed + "/" + total_stops;
            }
            
            current <- max_idx + 1;
        }
        
        write "\nResultats snapping :";
        write "  Reussis : " + snapped_stops + " (" + (snapped_stops * 100.0 / total_stops) with_precision 1 + "%)";
        write "  Warnings : " + warning_stops;
        write "  Echoues : " + failed_stops;
    }
    
    // SNAPPING D'UN STOP (OPTIMISE PAR ZONES)
    action process_stop_snapping(bus_stop s) {
        int zx <- int(s.location.x / grid_size);
        int zy <- int(s.location.y / grid_size);
        
        // Zones voisines
        list<int> neighbor_zone_ids <- [];
        loop offset over: neighbors {
            int nx <- zx + offset[0];
            int ny <- zy + offset[1];
            neighbor_zone_ids <+ (nx * 100000 + ny);
        }
        
        bool found <- false;
        float best_dist <- #max_float;
        edge_feature best_edge <- nil;
        
        // Recherche progressive par rayon
        loop radius over: search_radii {
            // Candidats dans zones voisines
            list<edge_feature> candidates <- edge_feature where (each.zone_id in neighbor_zone_ids);
            
            if !empty(candidates) {
                loop edge over: candidates {
                    float dist <- s distance_to edge.shape;
                    if dist < best_dist {
                        best_dist <- dist;
                        best_edge <- edge;
                    }
                }
                
                if best_edge != nil and best_dist <= radius {
                    found <- true;
                    break;
                }
            }
        }
        
        // Recherche globale si pas trouvé
        if !found {
            best_dist <- #max_float;
            best_edge <- nil;
            
            loop radius over: search_radii {
                loop edge over: edge_feature {
                    float dist <- s distance_to edge.shape;
                    if dist < best_dist {
                        best_dist <- dist;
                        best_edge <- edge;
                    }
                }
                
                if best_edge != nil and best_dist <= radius {
                    found <- true;
                    break;
                }
            }
        }
        
        // Appliquer le snapping
        if found and best_edge != nil {
            // Projeter le point sur l'arête
            list<point> closest_points <- best_edge.shape closest_points_with s.location;
            point projected_location <- first(closest_points);
            
            s.location <- projected_location;
            s.snapped_edge_id <- best_edge.edge_id;
            s.snap_distance <- best_dist;
            s.is_snapped <- true;
            
            snapped_stops <- snapped_stops + 1;
            
            if best_dist > 100.0 {
                s.snap_quality <- "warning";
                warning_stops <- warning_stops + 1;
            } else {
                s.snap_quality <- "good";
            }
            
        } else {
            s.is_snapped <- false;
            s.snap_quality <- "failed";
            failed_stops <- failed_stops + 1;
        }
    }
    
    // CONSTRUCTION MAPPINGS FINAUX
    action build_final_mappings {
        write "\n5. CONSTRUCTION MAPPINGS";
        
        ask bus_stop where (each.is_snapped) {
            if stopId != nil and stopId != "" {
                stopId_to_agent[stopId] <- self;
            }
        }
        
        write "Stops accessibles : " + length(stopId_to_agent);
    }
    
    // INDEXATION STOPS SUR GRAPHE
    action index_stops_on_graph {
        write "\n6. INDEXATION STOPS SUR GRAPHE";
        
        int indexed <- 0;
        
        ask bus_stop where (each.is_snapped) {
            // Trouver le nœud le plus proche manuellement
            point closest <- nil;
            float min_dist <- #max_float;
            
            loop vertex over: road_graph.vertices {
                point v_point <- point(vertex);
                float d <- location distance_to v_point;
                if d < min_dist {
                    min_dist <- d;
                    closest <- v_point;
                }
            }
            
            nearest_node <- closest;
            
            if nearest_node != nil {
                indexed <- indexed + 1;
            }
        }
        
        write "Stops indexes : " + indexed;
    }
    
    // CREATION VEHICULE ROBUSTE
    action create_specific_bus_robust {
        write "\n7. CREATION VEHICULE (APPROCHE ROBUSTE)";
        
        string target_stopId <- "01_1_S1";
        string target_tripId <- "01_1_MD_1";
        
        // Trouver le stop de départ
        bus_stop starter <- first(bus_stop where (each.stopId = target_stopId and each.is_snapped));
        
        if starter = nil {
            write "ERREUR: Stop " + target_stopId + " non trouve ou non snappe";
            return;
        }
        
        // Vérifier que le trip existe
        if starter.departureStopsInfo = nil or !(target_tripId in starter.departureStopsInfo.keys) {
            write "ERREUR: Trip " + target_tripId + " non trouve";
            return;
        }
        
        // Récupérer la séquence complète : list<pair<bus_stop, string_time>>
        list<pair<bus_stop, string>> stop_time_sequence <- starter.departureStopsInfo[target_tripId];
        
        if empty(stop_time_sequence) {
            write "ERREUR: Sequence vide";
            return;
        }
        
        // Extraire les stops et les temps
        list<bus_stop> trip_stops <- stop_time_sequence collect (each.key);
        list<string> departure_times <- stop_time_sequence collect (each.value);
        
        write "Nombre de stops : " + length(trip_stops);
        
        // Précalculer tous les chemins entre stops successifs
        list<path> precomputed_paths <- [];
        list<float> segment_distances <- [];
        list<float> segment_durations <- [];
        
        int path_errors <- 0;
        
        loop i from: 0 to: length(trip_stops) - 2 {
            bus_stop s1 <- trip_stops[i];
            bus_stop s2 <- trip_stops[i + 1];
            
            // Vérifier que les deux stops ont des vertices
            if s1.nearest_node = nil or s2.nearest_node = nil {
                write "ERREUR: Stop sans vertex - " + s1.stopName + " ou " + s2.stopName;
                path_errors <- path_errors + 1;
                add nil to: precomputed_paths;
                add 0.0 to: segment_distances;
                add 60.0 to: segment_durations;  // Default 1 min
                continue;
            }
            
            // Calculer le chemin entre les VERTICES
            path segment_path <- path_between(road_graph, s1.nearest_node, s2.nearest_node);
            
            if segment_path = nil {
                write "ATTENTION: Pas de chemin entre " + s1.stopName + " et " + s2.stopName;
                path_errors <- path_errors + 1;
                add nil to: precomputed_paths;
                add (s1.location distance_to s2.location) to: segment_distances;
                add 60.0 to: segment_durations;
            } else {
                add segment_path to: precomputed_paths;
                add segment_path.distance to: segment_distances;
                
                // Calculer la durée prévue (différence entre temps de départ)
                float duration <- parse_time_difference(departure_times[i], departure_times[i + 1]);
                add duration to: segment_durations;
            }
        }
        
        write "Chemins precalcules : " + length(precomputed_paths);
        write "Erreurs de calcul : " + path_errors;
        
        if path_errors > length(precomputed_paths) / 2 {
            write "ERREUR: Trop de chemins manquants, abandon";
            return;
        }
        
        // Créer le bus avec tous les chemins précalculés
        create bus with: [
            my_trip_id :: target_tripId,
            my_stops :: trip_stops,
            my_paths :: precomputed_paths,
            my_distances :: segment_distances,
            my_durations :: segment_durations,
            departure_times :: departure_times,
            current_idx :: 0,
            location :: trip_stops[0].location,
            gref :: road_graph
        ];
        
        write "Vehicule cree avec succes";
        write "  - " + length(trip_stops) + " stops";
        write "  - " + length(precomputed_paths) + " chemins";
    }
    
    // Parser la différence de temps (format HH:MM:SS)
    float parse_time_difference(string time1, string time2) {
        // Simple: convertir en secondes depuis minuit
        list<string> parts1 <- time1 split_with ":";
        list<string> parts2 <- time2 split_with ":";
        
        if length(parts1) < 3 or length(parts2) < 3 {
            return 60.0;  // Default 1 minute
        }
        
        float seconds1 <- (int(parts1[0]) * 3600.0) + (int(parts1[1]) * 60.0) + float(parts1[2]);
        float seconds2 <- (int(parts2[0]) * 3600.0) + (int(parts2[1]) * 60.0) + float(parts2[2]);
        
        float diff <- seconds2 - seconds1;
        
        // Gérer le passage de minuit
        if diff < 0 {
            diff <- diff + 86400.0;
        }
        
        return max(diff, 10.0);  // Au moins 10 secondes entre stops
    }
    
    // RAPPORT FINAL
    action final_report {
        write "\n========================================";
        write "RAPPORT FINAL - MATCHING COMPLET";
        write "========================================";
        
        float success_rate <- (snapped_stops * 100.0 / total_stops);
        
        write "\nSTATISTIQUES :";
        write "  Total stops : " + total_stops;
        write "  Snappes : " + snapped_stops + " (" + (success_rate with_precision 1) + "%)";
        write "  Warnings : " + warning_stops;
        write "  Echoues : " + failed_stops;
        
        write "\nGRAPHE :";
        write "  Aretes : " + length(edge_feature);
        write "  Graphe : " + (road_graph != nil ? "OK" : "ERREUR");
        
        write "\nVEHICULES :";
        write "  Bus crees : " + length(bus);
        
        write "\nEVALUATION :";
        if success_rate > 95 {
            write "EXCELLENT - Reseau pret pour simulation";
        } else if success_rate > 85 {
            write "BON - Quelques stops non matches";
        } else if success_rate > 70 {
            write "MOYEN - Problemes de couverture";
        } else {
            write "FAIBLE - Graphe incomplet";
        }
        
        write "\n========================================";
    }
}

// SPECIES BUS_STOP
species bus_stop skills: [TransportStopSkill] {
    string stopId;
    int snapped_edge_id <- -1;
    float snap_distance <- -1.0;
    bool is_snapped <- false;
    string snap_quality <- "none";
    int zone_id;
    point nearest_node <- nil;
    
    aspect base {
        rgb color <- is_snapped ? 
            (snap_quality = "good" ? #green : #orange) : #red;
        draw circle(100) color: color border: #black;
    }
}

// SPECIES EDGE_FEATURE
species edge_feature {
    int edge_id;
    int from_id;
    int to_id;
    float length_m;
    int zone_id;
    
    aspect base {
        draw shape color: #darkgreen width: 1.5;
    }
}

// SPECIES BUS (APPROCHE ROBUSTE)
species bus skills: [moving] {
    string my_trip_id;
    list<bus_stop> my_stops;
    list<path> my_paths;              // Chemins précalculés
    list<float> my_distances;         // Distances de chaque segment
    list<float> my_durations;         // Durées prévues de chaque segment
    list<string> departure_times;     // Temps de départ à chaque stop
    
    int current_idx <- 0;
    graph gref;
    bool at_terminus <- false;
    bool is_dwelling <- false;        // En arrêt au stop
    bool has_started <- false;        // NOUVEAU : flag pour éviter boucle
    float dwell_start <- 0.0;
    
    float current_segment_speed <- 7.0 #m/#s;
    
    // Commencer le trajet (UNE SEULE FOIS)
    reflex start_trip when: (!has_started) {
        has_started <- true;
        write "=== DEBUT TRIP " + my_trip_id + " ===";
        write "Depart : " + my_stops[0].stopName + " a " + departure_times[0];
        
        // Démarrer l'arrêt au premier stop
        is_dwelling <- true;
        dwell_start <- cycle * step;
    }
    
    // Partir du stop après le dwell time
    reflex leave_stop when: (is_dwelling and (cycle * step - dwell_start) >= dwell_time) {
        is_dwelling <- false;
        
        if current_idx < length(my_paths) {
            // Calculer la vitesse pour ce segment
            if my_durations[current_idx] > dwell_time {
                float travel_duration <- my_durations[current_idx] - dwell_time;
                current_segment_speed <- my_distances[current_idx] / travel_duration;
                
                // NOUVEAU : Limiter à la vitesse maximum
                float max_speed_ms <- max_speed / 3.6;  // Convertir km/h en m/s
                if current_segment_speed > max_speed_ms {
                    current_segment_speed <- max_speed_ms;
                    write "Vitesse limitee a " + max_speed + " km/h";
                }
                
                write "Depart vers " + my_stops[current_idx + 1].stopName + 
                      " (dist: " + (my_distances[current_idx] with_precision 0) + " m, " +
                      "duree GTFS: " + (my_durations[current_idx] with_precision 0) + " s, " +
                      "vitesse: " + ((current_segment_speed * 3.6) with_precision 1) + " km/h)";
            } else {
                current_segment_speed <- 10.0 #m/#s;  // Vitesse par défaut si durée trop courte
            }
        }
    }
    
    // Se déplacer en suivant le chemin précalculé
reflex move when: (!is_dwelling and !at_terminus and current_idx < length(my_paths)) {
    path current_path <- my_paths[current_idx];
    
    if current_path = nil {
        // Pas de chemin : téléportation
        location <- my_stops[current_idx + 1].location;
        write "TELEPORTATION vers " + my_stops[current_idx + 1].stopName;
        do arrive_at_stop;
    } else {
        // Suivre le chemin précalculé avec la vitesse dynamique
        do follow path: current_path speed: current_segment_speed return_path: false;
        
        // Vérifier si arrivé au stop
        float dist_to_next <- location distance_to my_stops[current_idx + 1].location;
        
        // Si très proche ou si current_path devient nil (fin du chemin)
        if dist_to_next <= 25.0 #m or current_path = nil {
            location <- my_stops[current_idx + 1].location;
            do arrive_at_stop;
        }
    }
}
    
    // Arriver à un stop
    action arrive_at_stop {
        current_idx <- current_idx + 1;
        
        write "ARRIVEE : " + my_stops[current_idx].stopName + 
              " (" + current_idx + "/" + (length(my_stops) - 1) + ") a " + 
              departure_times[current_idx];
        
        if current_idx < length(my_stops) - 1 {
            // Commencer l'arrêt
            is_dwelling <- true;
            dwell_start <- cycle * step;
        } else {
            // Terminus
            at_terminus <- true;
            write "=== TERMINUS ATTEINT ===";
        }
    }
    
    aspect base {
        rgb color <- at_terminus ? #orange : (is_dwelling ? #yellow : #red);
        draw circle(150) color: color border: #black;
        if !is_dwelling {
            draw triangle(200) color: #blue rotate: heading + 90;
        }
    }
}

// EXPERIMENT
experiment Matching type: gui {
    parameter "Taille grille (m)" var: grid_size min: 100 max: 1000 category: "Zones";
    parameter "Batch size" var: batch_size min: 100 max: 2000 category: "Performance";
    parameter "Dwell time (s)" var: dwell_time min: 10.0 max: 120.0 category: "Simulation";
    parameter "Vitesse max (km/h)" var: max_speed min: 20.0 max: 100.0 category: "Simulation";
    
    output {
        display "Reseau + Stops + Bus" background: #white type: 2d {
            species edge_feature aspect: base;
            species bus_stop aspect: base;
            species bus aspect: base;
            
            overlay position: {10, 10} size: {280 #px, 200 #px} 
                    background: #white transparency: 0.9 border: #black {
                draw "MATCHING GTFS-GRAPH" at: {10#px, 20#px} 
                     color: #black font: font("Arial", 12, #bold);
                
                draw "STOPS" at: {15#px, 45#px} 
                     color: #black font: font("Arial", 10, #bold);
                draw "Total : " + total_stops at: {20#px, 60#px} color: #black;
                draw "Snappes : " + snapped_stops at: {20#px, 75#px} color: #green;
                
                float rate <- total_stops > 0 ? (snapped_stops * 100.0 / total_stops) : 0.0;
                draw "Taux : " + (rate with_precision 1) + "%" at: {20#px, 90#px} 
                     color: (rate > 90 ? #green : (rate > 70 ? #orange : #red));
                
                draw "BUS" at: {15#px, 115#px} 
                     color: #black font: font("Arial", 10, #bold);
                draw "Actifs : " + length(bus where (!each.at_terminus and !each.is_dwelling)) 
                     at: {20#px, 130#px} color: #red;
                draw "En arret : " + length(bus where each.is_dwelling) 
                     at: {20#px, 145#px} color: #yellow;
                draw "Terminus : " + length(bus where each.at_terminus) 
                     at: {20#px, 160#px} color: #orange;
                     
                draw "Aretes : " + length(edge_feature) at: {20#px, 180#px} color: #darkgreen;
            }
        }
        
        monitor "Taux succes %" value: total_stops > 0 ? 
            ((snapped_stops * 100.0 / total_stops) with_precision 1) : 0.0;
        monitor "Bus en mouvement" value: length(bus where (!each.at_terminus and !each.is_dwelling));
        monitor "Bus en arret" value: length(bus where each.is_dwelling);
        monitor "Bus terminus" value: length(bus where each.at_terminus);
    }
}