/**
 * Name: GTFS_Graph_Matching_With_FakeShapes
 * Description: Chargement graphe + Matching stops + FAKE SHAPES (logique Java)
 * Tags: GTFS, graph, matching, fake-shapes, robust
 * Date: 2025-11-18
 */

model GTFS_Graph_Matching_With_FakeShapes

global {
    // --- FICHIERS ---
    string results_folder <- "../../results1/";
    gtfs_file gtfs_f <- gtfs_file("../../includes/nantes_gtfs");
    file data_file <- shape_file("../../includes/shapeFileNantes.shp");
    date starting_date <- date("2025-05-13T05:00:00");
    geometry shape <- envelope(data_file);
    
    // --- PARAMETRES MATCHING ---
    int grid_size <- 300;
    list<float> search_radii <- [50.0, 100.0, 200.0];
    int batch_size <- 500;
    
    // --- PARAMETRES SIMULATION ---
    float dwell_time <- 30.0 #s;
    float max_speed <- 50.0 #km/#h;
    
    // --- GRAPHE ---
    graph road_graph;
    
    // --- STATISTIQUES ---
    int total_stops <- 0;
    int snapped_stops <- 0;
    int warning_stops <- 0;
    int failed_stops <- 0;
    
    // ✅ NOUVEAU : Stats fake shapes
    int fake_edges_created <- 0;
    int fake_paths_created <- 0;
    
    // --- STRUCTURES ---
    map<string, bus_stop> stopId_to_agent <- [];
    list<pair<int,int>> neighbors <- [
        {0,0}, {-1,0}, {1,0}, {0,-1}, {0,1},
        {-1,-1}, {-1,1}, {1,-1}, {1,1}
    ];

    init {
        write "=== MATCHING GTFS + GRAPH + FAKE SHAPES ===\n";
        
        // 1-4. Workflow normal
        do load_graph_from_shapefile;
        do load_gtfs_stops;
        do assign_zones;
        do snap_stops_with_zones;
        
        // ✅ 5. NOUVEAU : Créer fake edges pour stops isolés (logique Java)
        do create_fake_edges_for_orphans;
        
        // 6-7. Suite du workflow
        do build_final_mappings;
        do index_stops_on_graph;
        
        // ✅ 8. NOUVEAU : Créer fake paths dans les trips (logique Java)
        do create_specific_bus_with_fake_paths;
        
        // 9. Rapport incluant fake shapes
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
            length_m :: float(read("length_m")),
            is_fake :: false  // ✅ Edges réelles = false
        ];
        
        write "Aretes chargees : " + length(edge_feature);
        
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
        
        ask bus_stop {
            zone_id <- (int(location.x / grid_size) * 100000) + int(location.y / grid_size);
        }
        
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
    
    // SNAPPING D'UN STOP
    action process_stop_snapping(bus_stop s) {
        int zx <- int(s.location.x / grid_size);
        int zy <- int(s.location.y / grid_size);
        
        list<int> neighbor_zone_ids <- [];
        loop offset over: neighbors {
            int nx <- zx + offset[0];
            int ny <- zy + offset[1];
            neighbor_zone_ids <+ (nx * 100000 + ny);
        }
        
        bool found <- false;
        float best_dist <- #max_float;
        edge_feature best_edge <- nil;
        
        loop radius over: search_radii {
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
        
        if found and best_edge != nil {
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
    
    // ✅ NOUVEAU : CREATION FAKE EDGES POUR STOPS ORPHELINS (LOGIQUE JAVA)
    action create_fake_edges_for_orphans {
        write "\n5. CREATION FAKE EDGES (LOGIQUE JAVA buildFakeShapesLazily)";
        
        list<bus_stop> orphans <- bus_stop where (!each.is_snapped);
        
        if empty(orphans) {
            write "Aucun stop orphelin, pas de fake edges necessaires";
            return;
        }
        
        write "Stops orphelins detectes : " + length(orphans);
        
        int created <- 0;
        
        ask orphans {
            // Trouver l'edge réelle la plus proche (comme Java trouve les stops dans la séquence)
            edge_feature closest <- edge_feature where (!each.is_fake) with_min_of (each.shape distance_to location);
            
            if closest != nil {
                // Point de connexion sur l'edge (comme Java : fake.addPoint(x, y))
                list<point> pts <- closest.shape closest_points_with location;
                point connection_point <- first(pts);
                
                float fake_dist <- location distance_to connection_point;
                
                // ✅ Créer un fake edge (comme Java : new TransportShape(fakeShapeId, routeId))
                create edge_feature with: [
                    shape :: polyline([location, connection_point]),  // Polyligne = fake shape
                    length_m :: fake_dist,
                    edge_id :: -1 * (created + 1),  // ID négatif pour identifier les fakes
                    from_id :: -1,
                    to_id :: closest.from_id,
                    is_fake :: true,  // ✅ Marquer comme fake (logique Java)
                    zone_id :: zone_id
                ];
                
                created <- created + 1;
                
                // Mettre à jour le stop
                is_snapped <- true;
                snap_quality <- "fake_connection";
                snapped_edge_id <- -1 * created;
                
                write "  Fake edge cree : Stop " + stopName + " -> Edge " + closest.edge_id + 
                      " (dist: " + (fake_dist with_precision 0) + "m)";
            }
        }
        
        fake_edges_created <- created;
        
        // ✅ Reconstruire le graphe avec les fake edges (comme Java met à jour shapesMap)
        if created > 0 {
            road_graph <- as_edge_graph(edge_feature);
            write "Graphe reconstruit avec " + created + " fake edges";
        }
        
        write "Total fake edges crees : " + fake_edges_created;
    }
    
    // CONSTRUCTION MAPPINGS FINAUX
    action build_final_mappings {
        write "\n6. CONSTRUCTION MAPPINGS";
        
        ask bus_stop where (each.is_snapped) {
            if stopId != nil and stopId != "" {
                stopId_to_agent[stopId] <- self;
            }
        }
        
        write "Stops accessibles : " + length(stopId_to_agent);
    }
    
    // INDEXATION STOPS SUR GRAPHE
    action index_stops_on_graph {
        write "\n7. INDEXATION STOPS SUR GRAPHE";
        
        int indexed <- 0;
        
        ask bus_stop where (each.is_snapped) {
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
    
    // ✅ NOUVEAU : CREATION BUS AVEC FAKE PATHS (LOGIQUE JAVA createTransportObjectsWithFakeShapes)
    action create_specific_bus_with_fake_paths {
        write "\n8. CREATION VEHICULE AVEC FAKE PATHS (LOGIQUE JAVA)";
        
        string target_stopId <- "XJAN1";
        string target_tripId <- "44958927-CR_24_25-HT25P201-L-Ma-Me-J-11"; 
        
        bus_stop starter <- first(bus_stop where (each.stopId = target_stopId and each.is_snapped));
        
        if starter = nil {
            write "ERREUR: Stop " + target_stopId + " non trouve ou non snappe";
            return;
        }
        
        if starter.departureStopsInfo = nil or !(target_tripId in starter.departureStopsInfo.keys) {
            write "ERREUR: Trip " + target_tripId + " non trouve";
            return;
        }
        
        list<pair<bus_stop, string>> stop_time_sequence <- starter.departureStopsInfo[target_tripId];
        
        if empty(stop_time_sequence) {
            write "ERREUR: Sequence vide";
            return;
        }
        
        list<bus_stop> trip_stops <- stop_time_sequence collect (each.key);
        list<string> departure_times <- stop_time_sequence collect (each.value);
        
        write "Nombre de stops : " + length(trip_stops);
        
        // Précalculer tous les chemins (avec création de fake paths si nécessaire)
        list<path> precomputed_paths <- [];
        list<float> segment_distances <- [];
        list<float> segment_durations <- [];
        list<bool> segment_is_fake <- [];  // ✅ Tracker les fake paths
        
        int path_errors <- 0;
        int fake_paths_count <- 0;
        
        loop i from: 0 to: length(trip_stops) - 2 {
            bus_stop s1 <- trip_stops[i];
            bus_stop s2 <- trip_stops[i + 1];
            
            if s1.nearest_node = nil or s2.nearest_node = nil {
                write "ERREUR: Stop sans vertex - " + s1.stopName + " ou " + s2.stopName;
                path_errors <- path_errors + 1;
                add nil to: precomputed_paths;
                add 0.0 to: segment_distances;
                add 60.0 to: segment_durations;
                add false to: segment_is_fake;
                continue;
            }
            
            // Calcul du chemin normal
            path segment_path <- path_between(road_graph, s1.nearest_node, s2.nearest_node);
            
            if segment_path = nil {
                // ✅ LOGIQUE JAVA : Créer un fake path direct (comme Java construit fake shapes)
                write "⚠️ Pas de chemin, creation FAKE PATH : " + s1.stopName + " -> " + s2.stopName;
                
                // Créer une polyligne directe (comme Java : pts.add(stop.getLocation()))
                geometry fake_geom <- polyline([s1.location, s2.location]);
                float fake_dist <- s1.location distance_to s2.location;
                
                // Option 1 : Path direct depuis la géométrie
                path fake_path <- path(fake_geom);
                
                add fake_path to: precomputed_paths;
                add fake_dist to: segment_distances;
                add true to: segment_is_fake;  // ✅ Marquer comme fake
                
                fake_paths_count <- fake_paths_count + 1;
                path_errors <- path_errors + 1;
                
                // Calculer durée
                float duration <- parse_time_difference(departure_times[i], departure_times[i + 1]);
                add duration to: segment_durations;
                
            } else {
                // Chemin normal trouvé
                add segment_path to: precomputed_paths;
                add segment_path.distance to: segment_distances;
                add false to: segment_is_fake;
                
                float duration <- parse_time_difference(departure_times[i], departure_times[i + 1]);
                add duration to: segment_durations;
            }
        }
        
        fake_paths_created <- fake_paths_count;
        
        write "Chemins precalcules : " + length(precomputed_paths);
        write "Chemins reels : " + (length(precomputed_paths) - fake_paths_count);
        write "Fake paths crees : " + fake_paths_count;
        write "Erreurs totales : " + path_errors;
        
        if path_errors > length(precomputed_paths) / 2 {
            write "AVERTISSEMENT: Plus de 50% de chemins manquants, mais on continue grace aux fake paths";
        }
        
        // Créer le bus
        create bus with: [
            my_trip_id :: target_tripId,
            my_stops :: trip_stops,
            my_paths :: precomputed_paths,
            my_distances :: segment_distances,
            my_durations :: segment_durations,
            departure_times :: departure_times,
            segment_is_fake :: segment_is_fake,  // ✅ Transmettre l'info fake
            current_idx :: 0,
            location :: trip_stops[0].location,
            gref :: road_graph
        ];
        
        write "Vehicule cree avec succes (avec fake paths si necessaires)";
        write "  - " + length(trip_stops) + " stops";
        write "  - " + length(precomputed_paths) + " chemins (" + fake_paths_count + " fakes)";
    }
    
    // Parser la différence de temps
    float parse_time_difference(string time1, string time2) {
        list<string> parts1 <- time1 split_with ":";
        list<string> parts2 <- time2 split_with ":";
        
        if length(parts1) < 3 or length(parts2) < 3 {
            return 60.0;
        }
        
        float seconds1 <- (int(parts1[0]) * 3600.0) + (int(parts1[1]) * 60.0) + float(parts1[2]);
        float seconds2 <- (int(parts2[0]) * 3600.0) + (int(parts2[1]) * 60.0) + float(parts2[2]);
        
        float diff <- seconds2 - seconds1;
        
        if diff < 0 {
            diff <- diff + 86400.0;
        }
        
        return max(diff, 10.0);
    }
    
    // ✅ RAPPORT FINAL AVEC FAKE SHAPES
    action final_report {
        write "\n========================================";
        write "RAPPORT FINAL - MATCHING + FAKE SHAPES";
        write "========================================";
        
        float success_rate <- (snapped_stops * 100.0 / total_stops);
        
        write "\nSTATISTIQUES STOPS :";
        write "  Total stops : " + total_stops;
        write "  Snappes (reels) : " + (snapped_stops - fake_edges_created) + 
              " (" + ((snapped_stops - fake_edges_created) * 100.0 / total_stops) with_precision 1 + "%)";
        write "  Connectes par fake : " + fake_edges_created;
        write "  Warnings : " + warning_stops;
        write "  Echoues : " + failed_stops;
        write "  TOTAL ACTIFS : " + snapped_stops + " (" + (success_rate with_precision 1) + "%)";
        
        write "\nGRAPHE :";
        int real_edges <- length(edge_feature where (!each.is_fake));
        int fake_edges <- length(edge_feature where (each.is_fake));
        write "  Aretes reelles : " + real_edges;
        write "  Fake edges : " + fake_edges;
        write "  TOTAL : " + length(edge_feature);
        write "  Graphe : " + (road_graph != nil ? "OK" : "ERREUR");
        
        write "\nVEHICULES :";
        write "  Bus crees : " + length(bus);
        if !empty(bus) {
            bus b <- first(bus);
            int real_paths <- 0;
            int fake_paths <- 0;
            loop i from: 0 to: length(b.segment_is_fake) - 1 {
                if b.segment_is_fake[i] {
                    fake_paths <- fake_paths + 1;
                } else {
                    real_paths <- real_paths + 1;
                }
            }
            write "  Chemins reels : " + real_paths;
            write "  Fake paths : " + fake_paths;
        }
        
        write "\nFAKE SHAPES (LOGIQUE JAVA) :";
        write "  Fake edges crees : " + fake_edges_created;
        write "  Fake paths crees : " + fake_paths_created;
        write "  TOTAL FAKE : " + (fake_edges_created + fake_paths_created);
        
        if fake_edges_created + fake_paths_created > 0 {
            write "\n⚠️ RESEAU INCOMPLET : " + (fake_edges_created + fake_paths_created) + 
                  " segments synthetiques crees (logique Java)";
        }
        
        write "\nEVALUATION :";
        if success_rate > 95 and fake_edges_created = 0 {
            write "EXCELLENT - Reseau complet, aucun fake necessaire";
        } else if success_rate > 95 {
            write "TRES BON - Reseau complet grace aux fake shapes";
        } else if success_rate > 85 {
            write "BON - Quelques stops non matches";
        } else if success_rate > 70 {
            write "MOYEN - Problemes de couverture";
        } else {
            write "FAIBLE - Graphe tres incomplet";
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
        // ✅ Couleur selon type de connexion
        rgb color <- !is_snapped ? #red : 
                     (snap_quality = "fake_connection" ? #magenta :  // Violet pour fake
                      (snap_quality = "good" ? #green : #orange));
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
    bool is_fake <- false;  // ✅ NOUVEAU : Identifier les fake edges
    
    aspect base {
        // ✅ Rouge pour fake edges, vert pour réelles
        rgb color <- is_fake ? #red : #darkgreen;
        int width <- is_fake ? 3 : 1;  // Plus épais pour les fakes
        draw shape color: color width: width;
    }
}

// SPECIES BUS
species bus skills: [moving] {
    string my_trip_id;
    list<bus_stop> my_stops;
    list<path> my_paths;
    list<float> my_distances;
    list<float> my_durations;
    list<string> departure_times;
    list<bool> segment_is_fake <- [];  // ✅ NOUVEAU : Tracker fake paths
    
    int current_idx <- 0;
    graph gref;
    bool at_terminus <- false;
    bool is_dwelling <- false;
    bool has_started <- false;
    float dwell_start <- 0.0;
    
    float current_segment_speed <- 7.0 #m/#s;
    
    int cycles_stuck <- 0;
    int max_cycles_per_segment <- 500;
    float last_distance_to_target <- 999999.0;
    
    reflex start_trip when: (!has_started) {
        has_started <- true;
        write "=== DEBUT TRIP " + my_trip_id + " ===";
        write "Depart : " + my_stops[0].stopName + " a " + departure_times[0];
        
        is_dwelling <- true;
        dwell_start <- cycle * step;
    }
    
    reflex leave_stop when: (is_dwelling and (cycle * step - dwell_start) >= dwell_time) {
        is_dwelling <- false;
        cycles_stuck <- 0;
        last_distance_to_target <- 999999.0;
        
        if current_idx < length(my_paths) {
            if my_durations[current_idx] > dwell_time {
                float travel_duration <- my_durations[current_idx] - dwell_time;
                current_segment_speed <- my_distances[current_idx] / travel_duration;
                
                float max_speed_ms <- max_speed / 3.6;
                if current_segment_speed > max_speed_ms {
                    current_segment_speed <- max_speed_ms;
                }
                
                // ✅ Indiquer si on va suivre un fake path
                string path_type <- segment_is_fake[current_idx] ? " [FAKE PATH]" : "";
                write "Depart vers " + my_stops[current_idx + 1].stopName + path_type +
                      " (dist: " + (my_distances[current_idx] with_precision 0) + " m, " +
                      "vitesse: " + ((current_segment_speed * 3.6) with_precision 1) + " km/h)";
            } else {
                current_segment_speed <- 10.0 #m/#s;
            }
        }
    }
    
    reflex move when: (!is_dwelling and !at_terminus and current_idx < length(my_paths)) {
        path current_path <- my_paths[current_idx];
        bus_stop target_stop <- my_stops[current_idx + 1];
        
        if current_path = nil {
            write "⚠️ Path manquant, forçage arrêt suivant";
            do arrive_at_stop;
            return;
        }
        
        float dist_before <- location distance_to target_stop.location;
        
        if dist_before <= 15.0 #m {
            write "✅ Arrivée proche détectée (" + (dist_before with_precision 1) + "m)";
            do arrive_at_stop;
            return;
        }
        
        if abs(dist_before - last_distance_to_target) < 1.0 {
            cycles_stuck <- cycles_stuck + 1;
        } else {
            cycles_stuck <- 0;
        }
        last_distance_to_target <- dist_before;
        
        if cycles_stuck > max_cycles_per_segment {
            write "⚠️ TIMEOUT: Bus bloqué " + cycles_stuck + " cycles, forçage arrêt";
            do arrive_at_stop;
            return;
        }
        
        do follow path: current_path speed: current_segment_speed return_path: false;
        
        float dist_to_network <- 999999.0;
        edge_feature closest_edge <- edge_feature with_min_of (each.shape distance_to location);
        if closest_edge != nil {
            dist_to_network <- closest_edge.shape distance_to location;
        }
        
        if dist_to_network > 50.0 #m {
            if closest_edge != nil {
                list<point> closest_points <- closest_edge.shape closest_points_with location;
                if !empty(closest_points) {
                    location <- first(closest_points);
                }
            }
        }
        
        float dist_after <- location distance_to target_stop.location;
        
        if dist_after <= 20.0 #m {
            write "✅ Arrivée post-mouvement (" + (dist_after with_precision 1) + "m)";
            do arrive_at_stop;
            return;
        }
        
        point next_node <- target_stop.nearest_node;
        if next_node != nil {
            float dist_to_node <- location distance_to next_node;
            if dist_to_node <= 25.0 #m {
                write "✅ Arrivée au vertex (" + (dist_to_node with_precision 1) + "m)";
                do arrive_at_stop;
                return;
            }
        }
    }
    
    action arrive_at_stop {
        current_idx <- current_idx + 1;
        cycles_stuck <- 0;
        
        if current_idx >= length(my_stops) {
            at_terminus <- true;
            write "=== TERMINUS ATTEINT ===";
            return;
        }
        
        bus_stop dst <- my_stops[current_idx];
        
        location <- dst.location;
        
        edge_feature e2 <- one_of(edge_feature where (each.edge_id = dst.snapped_edge_id));
        if e2 != nil {
            point on_edge <- first(e2.shape closest_points_with dst.location);
            if on_edge != nil {
                location <- on_edge;
            }
        }
        
        write "🚏 ARRIVEE : " + dst.stopName + 
              " (" + current_idx + "/" + (length(my_stops) - 1) + ")";
        
        if current_idx < length(my_stops) - 1 {
            is_dwelling <- true;
            dwell_start <- cycle * step;
        } else {
            at_terminus <- true;
            write "=== TERMINUS ATTEINT ===";
        }
    }
    
    aspect base {
        rgb color <- at_terminus ? #orange : (is_dwelling ? #yellow : #red);
        draw circle(150) color: color border: #black;
        
        if !is_dwelling and !at_terminus {
            draw triangle(200) color: #blue rotate: heading + 90;
            
            if current_idx < length(my_stops) - 1 {
                bus_stop next <- my_stops[current_idx + 1];
                float dist <- location distance_to next.location;
                
                // ✅ Afficher "FAKE" si on suit un fake path
                string label <- string(int(dist)) + "m";
                if current_idx < length(segment_is_fake) and segment_is_fake[current_idx] {
                    label <- label + " [FAKE]";
                }
                
                draw label color: #white font: font("Arial", 10, #bold) 
                     at: location + {0, -50};
            }
            
            if cycles_stuck > 50 {
                draw "STUCK!" color: #red font: font("Arial", 12, #bold) at: location + {0, -70};
            }
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
        display "Reseau + Stops + Bus + Fake Shapes" background: #white type: 2d {
            species edge_feature aspect: base;
            species bus_stop aspect: base;
            species bus aspect: base;
            
            overlay position: {10, 10} size: {300 #px, 240 #px} 
                    background: #white transparency: 0.9 border: #black {
                draw "MATCHING + FAKE SHAPES" at: {10#px, 20#px} 
                     color: #black font: font("Arial", 12, #bold);
                
                draw "STOPS" at: {15#px, 45#px} 
                     color: #black font: font("Arial", 10, #bold);
                draw "Total : " + total_stops at: {20#px, 60#px} color: #black;
                draw "Snappes (reels) : " + (snapped_stops - fake_edges_created) at: {20#px, 75#px} color: #green;
                draw "Fake connect : " + fake_edges_created at: {20#px, 90#px} color: #magenta;
                
                float rate <- total_stops > 0 ? (snapped_stops * 100.0 / total_stops) : 0.0;
                draw "Taux total : " + (rate with_precision 1) + "%" at: {20#px, 105#px} 
                     color: (rate > 90 ? #green : (rate > 70 ? #orange : #red));
                
                draw "GRAPHE" at: {15#px, 130#px} 
                     color: #black font: font("Arial", 10, #bold);
                int real_edges <- length(edge_feature where (!each.is_fake));
                int fake_edges <- length(edge_feature where (each.is_fake));
                draw "Aretes reelles : " + real_edges at: {20#px, 145#px} color: #darkgreen;
                draw "Fake edges : " + fake_edges at: {20#px, 160#px} color: #red;
                
                draw "BUS" at: {15#px, 185#px} 
                     color: #black font: font("Arial", 10, #bold);
                draw "Actifs : " + length(bus where (!each.at_terminus and !each.is_dwelling)) 
                     at: {20#px, 200#px} color: #red;
                draw "En arret : " + length(bus where each.is_dwelling) 
                     at: {20#px, 215#px} color: #yellow;
            }
        }
        
        monitor "Taux succes %" value: total_stops > 0 ? 
            ((snapped_stops * 100.0 / total_stops) with_precision 1) : 0.0;
        monitor "Fake edges" value: length(edge_feature where each.is_fake);
        monitor "Fake paths" value: fake_paths_created;
        monitor "Bus en mouvement" value: length(bus where (!each.at_terminus and !each.is_dwelling));
    }
}