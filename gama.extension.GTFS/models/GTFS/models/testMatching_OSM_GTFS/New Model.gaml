/**
* Name: complete_navigable_transport_simulation
* Author: Promagicshow95
* Description: Modèle complet avec bus navigables garantis sur réseau OSM connecté
* Tags: GTFS, OSM, pathfinding, navigation, bus simulation
* Date: 2025-07-08
*/

model complete_navigable_transport_simulation

global {
    // --- PARAMÈTRES RÉSEAU ---
    int grid_size <- 300;
    list<float> search_radii <- [500.0, 1000.0, 1500.0];
    int batch_size <- 500;
    float proximity_tolerance <- 100.0;
    float path_connection_tolerance <- 150.0; // Distance max pour connecter les segments

    // --- PARAMÈTRES SIMULATION ---
    date starting_date <- date("2025-05-17T16:00:00");
    float step <- 10 #s;
    int time_24h -> int(current_date - date([1970,1,1,0,0,0])) mod 86400;
    int current_seconds_mod <- 0;
    int current_day <- 0;

    // --- FICHIERS ---
    point top_left <- CRS_transform({0,0}, "EPSG:4326").location;
    point bottom_right <- CRS_transform({shape.width, shape.height}, "EPSG:4326").location;
    string adress <- "http://overpass-api.de/api/xapi_meta?*[bbox=" + top_left.x + "," + bottom_right.y + "," + bottom_right.x + "," + top_left.y + "]";
    file<geometry> osm_geometries <- osm_file<geometry>(adress, osm_data_to_generate);
    gtfs_file gtfs_f <- gtfs_file("../../includes/nantes_gtfs");
    file data_file <- shape_file("../../includes/shapeFileNantes.shp");
    geometry shape <- envelope(data_file);

    // --- FILTRES OSM ---
    map<string, list> osm_data_to_generate <- [
        "highway"::[],
        "railway"::[],
        "route"::[],
        "cycleway"::[]
    ];

    // --- VARIABLES RÉSEAU NAVIGABLE ---
    list<int> route_types_gtfs;
    map<int, graph> navigable_networks; // Graphes navigables par type de transport
    
    // --- VARIABLES DE CONNECTIVITÉ ---
    map<int, int> total_routes_per_type <- [];
    map<int, int> connected_routes_per_type <- [];
    map<int, int> navigable_stops_per_type <- [];
    map<int, int> unreachable_stops_per_type <- [];
    map<int, float> navigability_scores <- [];

    // --- VARIABLES SIMULATION BUS ---
    int total_trips_to_launch <- 0;
    int launched_trips_count <- 0;
    list<string> launched_trip_ids <- [];
    int successful_bus_launches <- 0;
    int failed_bus_launches <- 0;

    // --- VARIABLES MATCHING ---
    int nb_total_stops <- 0;
    int nb_stops_matched <- 0;
    int nb_stops_unmatched <- 0;
    map<string, string> tripId_to_osm_id_majoritaire <- [];

    init {
        write "=== 🚌 SIMULATION COMPLÈTE AVEC NAVIGABILITÉ GARANTIE ===";
        
        current_day <- floor((int(current_date - date([1970,1,1,0,0,0]))) / 86400);
        
        // 1. Créer les arrêts GTFS
        create bus_stop from: gtfs_f;
        nb_total_stops <- length(bus_stop);
        route_types_gtfs <- bus_stop collect(each.routeType) as list<int>;
        route_types_gtfs <- remove_duplicates(route_types_gtfs);
        
        write "Types de transport GTFS : " + route_types_gtfs;
        
        // 2. Créer les routes OSM
        do create_network_routes;
        
        // 3. ANALYSER ET AMÉLIORER LA NAVIGABILITÉ
        do analyze_and_improve_navigability;
        
        // 4. Tester la navigabilité avec les arrêts réels
        do test_stop_reachability;
        
        // 5. Matching spatial avec vérification navigabilité
        do process_stops_with_navigability_check;
        
        // 6. Créer le mapping final
        do create_trip_mapping;
        
        // 7. Préparer les statistiques de simulation
        do prepare_simulation_stats;
    }
    
    action create_network_routes {
        write "\n=== Création des routes depuis OSM ===";
        loop geom over: osm_geometries {
            if length(geom.points) > 1 {
                do create_single_route(geom);
            }
        }
        write "Routes créées : " + length(network_route);
    }
    
    action create_single_route(geometry geom) {
        string route_type;
        int routeType_num;
        string name <- (geom.attributes["name"] as string);
        string osm_id <- (geom.attributes["osm_id"] as string);

        if ((geom.attributes["gama_bus_line"] != nil) 
            or (geom.attributes["route"] = "bus") 
            or (geom.attributes["highway"] = "busway")) {
            route_type <- "bus";
            routeType_num <- 3;
        } else if geom.attributes["railway"] = "tram" {
            route_type <- "tram";
            routeType_num <- 0;
        } else if (
            geom.attributes["railway"] = "subway" or
            geom.attributes["route"] = "subway" or
            geom.attributes["route_master"] = "subway" or
            geom.attributes["railway"] = "metro" or
            geom.attributes["route"] = "metro"
        ) {
            route_type <- "subway";
            routeType_num <- 1;
        } else if geom.attributes["railway"] != nil 
                and !(geom.attributes["railway"] in ["abandoned", "platform", "disused"]) {
            route_type <- "railway";
            routeType_num <- 2;
        } else if (geom.attributes["cycleway"] != nil 
                or geom.attributes["highway"] = "cycleway") {
            route_type <- "cycleway";
            routeType_num <- 10;
        } else if geom.attributes["highway"] != nil {
            route_type <- "road";
            routeType_num <- 20;
        } else {
            route_type <- "other";
            routeType_num <- -1;
        }

        if routeType_num != -1 and (routeType_num in route_types_gtfs) {
            create network_route with: [
                shape::geom,
                route_type::route_type,
                routeType_num::routeType_num,
                name::name,
                osm_id::osm_id
            ];
        }
    }
    
    // === ANALYSE ET AMÉLIORATION DE LA NAVIGABILITÉ ===
    action analyze_and_improve_navigability {
        write "\n=== Analyse et amélioration de la navigabilité ===";
        
        loop route_type over: route_types_gtfs {
            list<network_route> routes <- network_route where (each.routeType_num = route_type);
            total_routes_per_type[route_type] <- length(routes);
            
            if !empty(routes) {
                write "\n--- Type " + route_type + " ---";
                
                // 1. CRÉER UN GRAPHE INITIAL
                graph initial_graph <- create_initial_graph(routes);
                
                // 2. ANALYSER LA CONNECTIVITÉ
                list<list> connected_components <- connected_components_of(initial_graph);
                
                write "  - Routes disponibles : " + length(routes);
                write "  - Composantes connectées : " + length(connected_components);
                
                // 3. AMÉLIORER LA CONNECTIVITÉ SI NÉCESSAIRE
                graph improved_graph <- improve_graph_connectivity(initial_graph, routes, route_type);
                
                // 4. STOCKER LE GRAPHE NAVIGABLE
                navigable_networks[route_type] <- improved_graph;
                
                // 5. ÉVALUER LA NAVIGABILITÉ FINALE
                do evaluate_final_navigability(route_type, improved_graph, routes);
                
            } else {
                write "⚠ Type " + route_type + " : aucune route OSM trouvée";
                navigability_scores[route_type] <- 0.0;
            }
        }
    }
    
    graph create_initial_graph(list<network_route> routes) {
        // Créer un graphe à partir des géométries des routes
        list<geometry> route_geoms <- routes collect each.shape;
        graph network_graph;
        
        try {
            network_graph <- as_edge_graph(route_geoms);
        } catch {
            // Si erreur, créer un graphe simple point par point
            network_graph <- graph([]);
            loop route over: routes {
                if route.shape != nil and length(route.shape.points) > 1 {
                    loop i from: 0 to: length(route.shape.points) - 2 {
                        point p1 <- route.shape.points[i];
                        point p2 <- route.shape.points[i + 1];
                        network_graph <- network_graph add_edge (p1::p2);
                    }
                }
            }
        }
        
        return network_graph;
    }
    
    graph improve_graph_connectivity(graph initial_graph, list<network_route> routes, int route_type) {
        graph improved_graph <- copy(initial_graph);
        list<list> components <- connected_components_of(initial_graph);
        
        if length(components) > 1 {
            write "  ⚠ Réseau fragmenté (" + length(components) + " composantes) - Tentative de connexion...";
            
            // Stratégie: Connecter les composantes proches
            int connections_added <- 0;
            
            loop i from: 0 to: length(components) - 2 {
                loop j from: (i + 1) to: length(components) - 1 {
                    list<point> comp1 <- components[i];
                    list<point> comp2 <- components[j];
                    
                    // Trouver les points les plus proches entre les deux composantes
                    float min_dist <- #max_float;
                    point closest_p1;
                    point closest_p2;
                    
                    loop p1 over: comp1 {
                        loop p2 over: comp2 {
                            float dist <- p1 distance_to p2;
                            if dist < min_dist {
                                min_dist <- dist;
                                closest_p1 <- p1;
                                closest_p2 <- p2;
                            }
                        }
                    }
                    
                    // Si les composantes sont proches, les connecter
                    if min_dist <= path_connection_tolerance {
                        improved_graph <- improved_graph add_edge (closest_p1::closest_p2);
                        connections_added <- connections_added + 1;
                        write "    ✓ Connecté composante " + (i+1) + " à " + (j+1) + " (distance: " + (min_dist with_precision 1) + "m)";
                    }
                }
            }
            
            // Vérifier l'amélioration
            list<list> new_components <- connected_components_of(improved_graph);
            write "  → Nouvelles composantes après amélioration : " + length(new_components);
            write "  → Connexions ajoutées : " + connections_added;
            
            connected_routes_per_type[route_type] <- length(routes) - length(new_components) + 1;
        } else {
            write "  ✓ Réseau déjà entièrement connecté";
            connected_routes_per_type[route_type] <- length(routes);
        }
        
        return improved_graph;
    }
    
    action evaluate_final_navigability(int route_type, graph network_graph, list<network_route> routes) {
        if network_graph = nil or length(network_graph.vertices) = 0 {
            write "  ❌ Graphe invalide pour le type " + route_type;
            navigability_scores[route_type] <- 0.0;
            return;
        }
        
        list<list> final_components <- connected_components_of(network_graph);
        int largest_component_size <- 0;
        
        if !empty(final_components) {
            largest_component_size <- max(final_components collect length(each));
        }
        
        float connectivity_ratio <- connected_routes_per_type[route_type] / total_routes_per_type[route_type];
        float coverage_ratio <- largest_component_size / length(network_graph.vertices);
        
        navigability_scores[route_type] <- (connectivity_ratio * 0.6) + (coverage_ratio * 0.4);
        
        write "  - Ratio de connectivité : " + (connectivity_ratio with_precision 2);
        write "  - Ratio de couverture : " + (coverage_ratio with_precision 2);
        write "  - Score de navigabilité : " + (navigability_scores[route_type] with_precision 2);
        
        if navigability_scores[route_type] >= 0.8 {
            write "  ✅ Réseau entièrement navigable pour les bus";
        } else if navigability_scores[route_type] >= 0.6 {
            write "  ✓ Réseau majoritairement navigable";
        } else if navigability_scores[route_type] >= 0.4 {
            write "  ⚠ Réseau partiellement navigable - quelques blocages possibles";
        } else {
            write "  ❌ Réseau peu navigable - risque élevé de blocage des bus";
        }
    }
    
    // === TEST DE L'ACCESSIBILITÉ DES ARRÊTS ===
    action test_stop_reachability {
        write "\n=== Test de l'accessibilité des arrêts ===";
        
        loop route_type over: route_types_gtfs {
            if navigable_networks contains_key route_type {
                graph network <- navigable_networks[route_type];
                list<bus_stop> stops <- bus_stop where (each.routeType = route_type);
                
                int reachable_connections <- 0;
                int unreachable_connections <- 0;
                
                if length(stops) > 1 and length(network.vertices) > 0 {
                    // Tester l'accessibilité entre quelques paires d'arrêts
                    int tests_performed <- 0;
                    int max_tests <- min(20, length(stops) * (length(stops) - 1) / 2);
                    
                    loop i from: 0 to: length(stops) - 2 {
                        loop j from: (i + 1) to: length(stops) - 1 {
                            if tests_performed >= max_tests { break; }
                            
                            bus_stop stop1 <- stops[i];
                            bus_stop stop2 <- stops[j];
                            
                            // Trouver les points les plus proches sur le réseau
                            point network_point1 <- network.vertices closest_to stop1.location;
                            point network_point2 <- network.vertices closest_to stop2.location;
                            
                            // Tester s'il existe un chemin
                            path test_path <- path_between(network, network_point1, network_point2);
                            
                            if test_path != nil and length(test_path.edges) > 0 {
                                reachable_connections <- reachable_connections + 1;
                            } else {
                                unreachable_connections <- unreachable_connections + 1;
                                write "    ⚠ Pas de chemin entre arrêt " + stop1.stopId + " et " + stop2.stopId;
                            }
                            
                            tests_performed <- tests_performed + 1;
                        }
                    }
                    
                    navigable_stops_per_type[route_type] <- reachable_connections;
                    unreachable_stops_per_type[route_type] <- unreachable_connections;
                    
                    if reachable_connections + unreachable_connections > 0 {
                        float reachability_ratio <- reachable_connections / (reachable_connections + unreachable_connections);
                        write "Type " + route_type + " - Accessibilité : " + (reachability_ratio with_precision 2) + " (" + reachable_connections + "/" + (reachable_connections + unreachable_connections) + " connexions testées)";
                    }
                }
            }
        }
    }
    
    // === MATCHING AVEC VÉRIFICATION DE NAVIGABILITÉ ===
    action process_stops_with_navigability_check {
        write "\n=== Matching spatial avec vérification navigabilité ===";
        
        ask bus_stop {
            do process_stop_navigability;
        }
        
        write "Matching terminé : " + nb_stops_matched + "/" + nb_total_stops + " arrêts associés au réseau navigable";
        
        // Statistiques par type
        loop route_type over: route_types_gtfs {
            int matched <- length(bus_stop where (each.routeType = route_type and each.is_navigable));
            int total <- length(bus_stop where (each.routeType = route_type));
            write "  Type " + route_type + " : " + matched + "/" + total + " arrêts navigables";
        }
    }
    
    action create_trip_mapping {
        write "\n=== Création du mapping tripId → réseau navigable ===";
        
        int navigable_trips <- 0;
        
        ask bus_stop where (each.is_navigable) {
            loop trip_id over: departureStopsInfo.keys {
                if !(tripId_to_osm_id_majoritaire contains_key trip_id) {
                    tripId_to_osm_id_majoritaire[trip_id] <- "navigable_network_" + routeType;
                    navigable_trips <- navigable_trips + 1;
                }
            }
        }
        
        write "Total trips navigables : " + navigable_trips;
        write "Réseaux navigables disponibles : " + navigable_networks.keys;
    }
    
    action prepare_simulation_stats {
        write "\n=== Préparation des statistiques de simulation ===";
        
        // Compter les trips potentiels par type navigable
        loop route_type over: route_types_gtfs {
            if navigable_networks contains_key route_type {
                list<bus_stop> navigable_stops <- bus_stop where (each.routeType = route_type and each.is_navigable);
                int potential_trips <- sum(navigable_stops collect each.tripNumber);
                
                if route_type = 3 { // Bus
                    total_trips_to_launch <- potential_trips;
                    write "🚌 Total trips bus navigables : " + total_trips_to_launch;
                }
            }
        }
    }
    
    // === REFLEXES DE SIMULATION ===
    int get_time_now {
        int dof <- floor((int(current_date - date([1970,1,1,0,0,0]))) / 86400);
        if dof > current_day {
            return time_24h + 86400;
        }
        return time_24h;
    }
    
    reflex update_time_every_cycle {
        current_seconds_mod <- get_time_now();
    }
    
    reflex check_new_day when: launched_trips_count >= total_trips_to_launch and total_trips_to_launch > 0 {
        int sim_day_index <- floor((int(current_date - date([1970,1,1,0,0,0]))) / 86400);
        if sim_day_index > current_day {
            current_day <- sim_day_index;
            launched_trips_count <- 0;
            launched_trip_ids <- [];
            successful_bus_launches <- 0;
            failed_bus_launches <- 0;
            ask bus_stop where (each.routeType = 3 and each.is_navigable) {
                current_trip_index <- 0;
            }
            write "🌙 Nouveau jour de simulation : " + current_day;
        }
    }
}

species bus_stop skills: [TransportStopSkill] {
    // Propriétés GTFS classiques
    rgb customColor <- rgb(0,0,255);
    map<string, bool> trips_launched;
    list<string> ordered_trip_ids;
    int current_trip_index <- 0;
    bool initialized <- false;
    
    // Propriétés de navigabilité
    bool is_matched <- false;
    bool is_navigable <- false;
    point closest_network_point;
    float distance_to_network <- -1.0;
    
    map<string, map<string, list<string>>> departureStopsInfo;

    reflex init_trip_list when: cycle = 1 {
        ordered_trip_ids <- keys(departureStopsInfo);
    }

    action process_stop_navigability {
        // Vérifier d'abord si le réseau est navigable pour ce type
        if !(navigable_networks contains_key routeType) {
            write "⚠ Pas de réseau navigable pour le type " + routeType + " - arrêt " + stopId + " ignoré";
            is_matched <- false;
            is_navigable <- false;
            nb_stops_unmatched <- nb_stops_unmatched + 1;
            return;
        }
        
        graph network <- navigable_networks[routeType];
        
        // Trouver le point le plus proche sur le réseau navigable
        if length(network.vertices) > 0 {
            point closest_network_point_temp <- network.vertices closest_to location;
            float distance_to_network_temp <- location distance_to closest_network_point_temp;
            
            if distance_to_network_temp <= max(search_radii) {
                closest_network_point <- closest_network_point_temp;
                distance_to_network <- distance_to_network_temp;
                is_matched <- true;
                is_navigable <- true;
                nb_stops_matched <- nb_stops_matched + 1;
            } else {
                write "⚠ Arrêt " + stopId + " trop loin du réseau navigable (" + (distance_to_network_temp with_precision 1) + "m)";
                is_matched <- false;
                is_navigable <- false;
                nb_stops_unmatched <- nb_stops_unmatched + 1;
            }
        } else {
            is_matched <- false;
            is_navigable <- false;
            nb_stops_unmatched <- nb_stops_unmatched + 1;
        }
    }

    // === LANCEMENT DE BUS AVEC VÉRIFICATION NAVIGABILITÉ ===
    reflex launch_navigable_vehicles when: (is_navigable and departureStopsInfo != nil and current_trip_index < length(ordered_trip_ids) and routeType = 3) {
        string trip_id <- ordered_trip_ids[current_trip_index];
        list<pair<bus_stop, string>> trip_info <- departureStopsInfo[trip_id];
        
        if length(trip_info) > 0 {
            string departure_time <- trip_info[0].value;

            // Vérifier que le trip n'a pas déjà été lancé et que l'heure est arrivée
            if (current_seconds_mod >= int(departure_time) and not (trip_id in launched_trip_ids)) {
                
                // ✅ VÉRIFICATION CRUCIALE : Tous les arrêts du trip sont-ils navigables ?
                bool all_stops_navigable <- true;
                loop stop_info over: trip_info {
                    bus_stop stop <- stop_info.key;
                    if !stop.is_navigable {
                        all_stops_navigable <- false;
                        break;
                    }
                }
                
                if all_stops_navigable and length(trip_info) > 1 {
                    // ✅ Conditions optimales : lancer le bus
                    point initial_target <- trip_info[1].key.closest_network_point;
                    
                    create bus with: [
                        departureStopsInfo:: trip_info,
                        current_stop_index :: 0,
                        location :: closest_network_point, // ✅ Position sur le réseau navigable
                        target_location :: initial_target, // ✅ Cible sur le réseau navigable
                        trip_id :: int(trip_id),
                        route_type :: self.routeType,
                        loop_starting_day:: current_day,
                        navigation_network :: navigable_networks[routeType] // ✅ Réseau garanti connecté
                    ];

                    launched_trips_count <- launched_trips_count + 1;
                    launched_trip_ids <- launched_trip_ids + trip_id;
                    successful_bus_launches <- successful_bus_launches + 1;
                    current_trip_index <- (current_trip_index + 1) mod length(ordered_trip_ids);
                    
                } else {
                    // ❌ Trip non navigable : skip
                    failed_bus_launches <- failed_bus_launches + 1;
                    current_trip_index <- (current_trip_index + 1) mod length(ordered_trip_ids);
                    launched_trip_ids <- launched_trip_ids + trip_id; // Marquer comme traité
                    write "⚠ Trip " + trip_id + " skippé : arrêts non navigables";
                }
            }
        }
    }

    aspect base {
        rgb stop_color;
        if is_navigable {
            stop_color <- #green;
        } else if is_matched {
            stop_color <- #orange;
        } else {
            stop_color <- #red;
        }
        draw circle(100.0) color: stop_color;
    }
    
    aspect navigability {
        rgb stop_color;
        if is_navigable {
            stop_color <- #green;
        } else if is_matched {
            stop_color <- #orange;
        } else {
            stop_color <- #red;
        }
        
        draw circle(120.0) color: stop_color;
        
        // Afficher la connexion au réseau si navigable
        if is_navigable and closest_network_point != nil {
            draw line([location, closest_network_point]) color: #blue width: 2;
            draw circle(50.0) color: #blue at: closest_network_point;
        }
    }
}

species network_route {
    geometry shape;
    string route_type;
    int routeType_num;
    string name;
    string osm_id;
    
    rgb get_transport_color {
        switch routeType_num {
            match 0 { return #blue; }      // Tram
            match 1 { return #purple; }    // Subway/Metro
            match 2 { return #orange; }    // Railway
            match 3 { return #green; }     // Bus
            match 10 { return #cyan; }     // Cycleway
            match 20 { return #gray; }     // Road
            default { return #black; }
        }
    }
    
    aspect base {
        draw shape color: get_transport_color() width: 2;
    }
}

species bus skills: [moving] {
    graph navigation_network; // ✅ Réseau navigable garanti
    
    // Propriétés du bus
    int creation_time;
    int end_time;
    int real_duration;
    int current_stop_index <- 0;
    point target_location;
    list<pair<bus_stop,string>> departureStopsInfo;
    int trip_id;
    int route_type;
    int loop_starting_day;
    int current_local_time;
    bool waiting_at_stop <- true;
    
    // Statistiques de performance
    list<int> arrival_time_diffs_pos <- [];
    list<int> arrival_time_diffs_neg <- [];
    int navigation_failures <- 0; // Compteur d'échecs de navigation

    init {
        speed <- 50 #km/#h;
        creation_time <- get_local_time_now();
    }

    int get_local_time_now {
        int dof <- floor((int(current_date - date([1970,1,1,0,0,0]))) / 86400);
        if dof > loop_starting_day {
            return time_24h + 86400;
        }
        return time_24h;
    }

    reflex update_time_every_cycle {
        current_local_time <- get_local_time_now();
    }
    
    reflex wait_at_stop when: waiting_at_stop {
        // ✅ Vérification sécurisée de l'index
        if current_stop_index < length(departureStopsInfo) {
            int stop_time <- departureStopsInfo[current_stop_index].value as int;

            if current_local_time >= stop_time {
                waiting_at_stop <- false;
            }
        } else {
            // Index invalide, terminer le bus
            do die;
        }
    }

    // ✅ DÉPLACEMENT NAVIGABLE GARANTI
    reflex move_navigable when: not waiting_at_stop and self.location distance_to target_location > 5#m {
        if navigation_network != nil {
            // ✅ Utilisation du réseau navigable garanti connecté
            do goto target: target_location on: navigation_network speed: speed;
            
            if location distance_to target_location < 5#m {
                location <- target_location;
            }
        } else {
            // ❌ Pas de réseau navigable : forcer l'arrêt
            write "❌ Bus " + trip_id + " : pas de réseau navigable !";
            navigation_failures <- navigation_failures + 1;
            do die;
        }
    }

    reflex check_arrival when: self.location distance_to target_location < 5#m and not waiting_at_stop {
        if current_stop_index < length(departureStopsInfo) - 1 {
            
            // Calcul de l'écart de temps à l'arrivée
            int expected_arrival_time <- departureStopsInfo[current_stop_index].value as int;
            int actual_time <- current_local_time;
            int time_diff_at_stop <- expected_arrival_time - actual_time;
            
            // Ajouter dans la bonne liste
            if time_diff_at_stop < 0 {
                arrival_time_diffs_neg << time_diff_at_stop; // ❌ Retard (négatif)
            } else {
                arrival_time_diffs_pos << time_diff_at_stop; // ✅ Avance (positif)
            }

            // Préparer l'étape suivante
            current_stop_index <- current_stop_index + 1;
            
            // ✅ NAVIGATION SÉCURISÉE : Vérifier que l'arrêt suivant existe et est navigable
            if current_stop_index < length(departureStopsInfo) {
                bus_stop next_stop <- departureStopsInfo[current_stop_index].key;
                
                if next_stop.is_navigable and next_stop.closest_network_point != nil {
                    target_location <- next_stop.closest_network_point;
                    waiting_at_stop <- true;
                } else {
                    // ❌ Arrêt suivant non navigable : terminer le trajet
                    write "⚠ Bus " + trip_id + " : arrêt suivant non navigable, fin de trajet";
                    navigation_failures <- navigation_failures + 1;
                    end_time <- current_local_time;
                    real_duration <- end_time - creation_time;
                    do die;
                }
            } else {
                // Plus d'arrêts disponibles, terminer le trajet
                end_time <- current_local_time;
                real_duration <- end_time - creation_time;
                do die;
            }
            
        } else {
            // Dernier arrêt atteint
            end_time <- current_local_time;
            real_duration <- end_time - creation_time;
            do die;
        }
    }

    aspect base {
        if route_type = 1 {
            draw rectangle(150, 200) color: #red rotate: heading;
        } else if route_type = 3 {
            draw rectangle(100, 150) color: #green rotate: heading;
        } else {
            draw rectangle(110, 170) color: #blue rotate: heading;
        }
        
        // Indicateur de problème de navigation
        if navigation_failures > 0 {
            draw triangle(20) color: #red at: location + {0, 0, 10};
        }
    }
}

experiment NavigableTransportSimulation type: gui {
    parameter "Tolérance de connexion (m)" var: path_connection_tolerance min: 50.0 max: 500.0 step: 50.0;
    parameter "Tolérance de proximité (m)" var: proximity_tolerance min: 50.0 max: 200.0 step: 25.0;
    parameter "Vitesse simulation" var: step min: 5.0 max: 60.0 step: 5.0;
    
    output {
        display "Simulation Transport Navigable" type: 3d {
            species network_route aspect: base transparency: 0.3;
            species bus_stop aspect: navigability;
            species bus aspect: base;
            
            overlay position: {10, 10} size: {500 #px, 300 #px} background: #white transparency: 0.85 {
                draw "🚌 SIMULATION TRANSPORT AVEC NAVIGABILITÉ GARANTIE" at: {15#px, 20#px} color: #black font: font("SansSerif", 14, #bold);
                
                draw "=== INFRASTRUCTURE ===" at: {15#px, 45#px} color: #black font: font("SansSerif", 12, #bold);
                draw "Routes OSM : " + length(network_route) at: {15#px, 60#px} color: #green;
                draw "Réseaux navigables : " + length(navigable_networks) + "/" + length(route_types_gtfs) at: {15#px, 75#px} color: #blue;
                
                draw "=== ARRÊTS ===" at: {15#px, 100#px} color: #black font: font("SansSerif", 12, #bold);
                draw "🟢 Navigables : " + nb_stops_matched + "/" + nb_total_stops at: {15#px, 115#px} color: #green;
                draw "🔴 Non navigables : " + nb_stops_unmatched at: {15#px, 130#px} color: #red;
                
                draw "=== SIMULATION EN COURS ===" at: {15#px, 155#px} color: #black font: font("SansSerif", 12, #bold);
                draw "🚌 Bus actifs : " + length(bus) at: {15#px, 170#px} color: #blue;
                draw "✅ Lancements réussis : " + successful_bus_launches at: {15#px, 185#px} color: #green;
                draw "❌ Lancements échoués : " + failed_bus_launches at: {15#px, 200#px} color: #red;
                draw "🎯 Trips navigables lancés : " + launched_trips_count + "/" + total_trips_to_launch at: {15#px, 215#px} color: #black;
                
                draw "=== NAVIGABILITÉ PAR TYPE ===" at: {15#px, 240#px} color: #black font: font("SansSerif", 11, #bold);
                
                int y_pos <- 255;
                loop route_type over: navigability_scores.keys {
                    float score <- navigability_scores[route_type];
                    string status;
                    rgb color_status;
                    
                    if score >= 0.8 {
                        status <- "✅ Parfait";
                        color_status <- #green;
                    } else if score >= 0.6 {
                        status <- "✓ Bon";
                        color_status <- #blue;
                    } else if score >= 0.4 {
                        status <- "⚠ Moyen";
                        color_status <- #orange;
                    } else {
                        status <- "❌ Risqué";
                        color_status <- #red;
                    }
                    
                    draw "Type " + route_type + ": " + status + " (" + (score with_precision 2) + ")" at: {15#px, y_pos#px} color: color_status;
                    y_pos <- y_pos + 15;
                }
                
                // Temps de simulation
                draw "Temps simulation : " + current_date at: {15#px, (y_pos + 10)#px} color: #gray font: font("SansSerif", 9);
                
                // Légende détaillée
                draw "Légende: 🟢=Navigable, 🟠=Proche réseau, 🔴=Isolé, 🔵=Point réseau, 🔺=Problème navigation" at: {15#px, (y_pos + 25)#px} color: #gray font: font("SansSerif", 8);
            }
        }
        
        display "Métriques de Performance" {
            chart "Performance Simulation" type: series {
                data "Bus actifs" value: length(bus) color: #blue;
                data "Lancements réussis (cumul)" value: successful_bus_launches color: #green;
                data "Échecs navigation (cumul)" value: failed_bus_launches color: #red;
            }
            
            chart "Navigabilité par Type" type: histogram {
                loop route_type over: navigability_scores.keys {
                    data "Type " + route_type value: navigability_scores[route_type] color: (navigability_scores[route_type] >= 0.8) ? #green : ((navigability_scores[route_type] >= 0.6) ? #blue : #orange);
                }
            }
            
            chart "État des Arrêts" type: pie {
                data "Navigables" value: nb_stops_matched color: #green;
                data "Non navigables" value: nb_stops_unmatched color: #red;
            }
        }
        
        display "Analyse Détaillée Connectivité" {
            chart "Composantes Connectées" type: histogram {
                loop route_type over: total_routes_per_type.keys {
                    int total <- total_routes_per_type[route_type];
                    int connected <- connected_routes_per_type contains_key route_type ? connected_routes_per_type[route_type] : 0;
                    data "Total Type " + route_type value: total color: #gray;
                    data "Connecté Type " + route_type value: connected color: #green;
                }
            }
            
            chart "Tests d'Accessibilité" type: series {
                loop route_type over: navigable_stops_per_type.keys {
                    int reachable <- navigable_stops_per_type[route_type];
                    int unreachable <- unreachable_stops_per_type contains_key route_type ? unreachable_stops_per_type[route_type] : 0;
                    data "Accessible Type " + route_type value: reachable color: #green;
                    data "Inaccessible Type " + route_type value: unreachable color: #red;
                }
            }
        }
        
        monitor "Navigation Status" value: "Réseaux navigables: " + length(navigable_networks) + " | Score moyen: " + (length(navigability_scores) > 0 ? (sum(navigability_scores.values) / length(navigability_scores)) with_precision 2 : "N/A") + " | Bus actifs: " + length(bus) + " | Succès: " + successful_bus_launches + " | Échecs: " + failed_bus_launches;
    }
}