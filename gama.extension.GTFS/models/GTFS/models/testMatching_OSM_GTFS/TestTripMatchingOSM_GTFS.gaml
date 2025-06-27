/**
* Name: GTFS_OSM_Bus_Simulation
* Author: Promagicshow95
* Description: Modèle combiné : matching GTFS-OSM + simulation de bus sur routes OSM
* Tags: GTFS, OSM, mapping, transport, simulation
* Date: 2025-06-25
*/

model GTFS_OSM_Bus_Simulation

global {
    // --- PARAMÈTRES MATCHING ---
    int grid_size <- 300;
    list<float> search_radii <- [500.0, 1000.0, 1500.0];
    int batch_size <- 500;

    // --- PARAMÈTRES SIMULATION ---
    string selected_trip_id <- "35703470-CR_24_25-HA25H1F6-Samedi-22"; // Trip à simuler
    int selected_stop_index <- 430; // Index de l'arrêt de départ
    date starting_date <- date("2025-05-17T16:00:00");
    float step <- 0.2 #s;

    // --- FICHIERS ---
    point top_left <- CRS_transform({0,0}, "EPSG:4326").location;
    point bottom_right <- CRS_transform({shape.width, shape.height}, "EPSG:4326").location;
    string adress <- "http://overpass-api.de/api/xapi_meta?*[bbox=" + top_left.x + "," + bottom_right.y + "," + bottom_right.x + "," + top_left.y + "]";
    file<geometry> osm_geometries <- osm_file<geometry>(adress, osm_data_to_generate);
    //file<geometry> osm_geometries <- osm_file("../../includes/Nantes_map (2).osm", osm_data_to_generate);
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

    // --- VARIABLES MATCHING ---
    list<int> route_types_gtfs;
    list<pair<int,int>> neighbors <- [
        {0,0}, {-1,0}, {1,0}, {0,-1}, {0,1},
        {-1,-1}, {-1,1}, {1,-1}, {1,1}
    ];
    int nb_total_stops <- 0;
    int nb_stops_matched <- 0;
    int nb_stops_unmatched <- 0;

    // --- MAPPING FINAL ---
    map<string, int> tripId_to_route_index_majoritaire <- [];
    
    // --- VARIABLES SIMULATION ---
    graph route_network;
    list<bus_stop> trip_bus_stops;
    bus_stop starts_stop;
    map<int, graph> route_graphs;
    int selected_route_index;

    init {
        write "=== Initialisation du modèle combiné ===";
        
        // PHASE 1 : MATCHING GTFS-OSM
        write "\n--- PHASE 1 : MATCHING GTFS-OSM ---";
        
        create bus_stop from: gtfs_f;
        nb_total_stops <- length(bus_stop);
        route_types_gtfs <- bus_stop collect(each.routeType) as list<int>;
        route_types_gtfs <- remove_duplicates(route_types_gtfs);
        
        write "Types de transport GTFS trouvés : " + route_types_gtfs;
        
        do create_network_routes;
        do assign_zones;
        do process_stops;
        do create_trip_mapping;
        
        // PHASE 2 : PRÉPARATION SIMULATION
        write "\n--- PHASE 2 : PRÉPARATION SIMULATION ---";
        
        do prepare_simulation;
        
        // PHASE 3 : LANCEMENT SIMULATION
        write "\n--- PHASE 3 : LANCEMENT SIMULATION ---";
        
        do launch_bus_simulation;
    }
    
    // === ACTIONS DE MATCHING (inchangées) ===
    
    action create_network_routes {
        write "Création des routes depuis OSM...";
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
    
    action assign_zones {
        write "Attribution des zones spatiales...";
        ask bus_stop {
            zone_id <- (int(location.x / grid_size) * 100000) + int(location.y / grid_size);
        }
        ask network_route {
            point centroid <- shape.location;
            zone_id <- (int(centroid.x / grid_size) * 100000) + int(centroid.y / grid_size);
        }
    }
    
    action create_trip_mapping {
        write "\nCréation du mapping tripId → route_index...";
        
        map<string, list<int>> temp_mapping <- [];

        ask bus_stop where (each.is_matched) {
            loop trip_id over: departureStopsInfo.keys {
                if (temp_mapping contains_key trip_id) {
                    temp_mapping[trip_id] <+ closest_route_index;
                } else {
                    temp_mapping[trip_id] <- [closest_route_index];
                }
            }
        }
        
        loop trip_id over: temp_mapping.keys {
            list<int> indices <- temp_mapping[trip_id];
            map<int, int> counter <- [];
            
            loop idx over: indices {
                counter[idx] <- (counter contains_key idx) ? counter[idx] + 1 : 1;
            }
            
            int majority_index <- -1;
            int max_count <- 0;
            loop idx over: counter.keys {
                if counter[idx] > max_count {
                    max_count <- counter[idx];
                    majority_index <- idx;
                }
            }
            tripId_to_route_index_majoritaire[trip_id] <- majority_index;
        }
        
        write "\nRésultats du mapping (10 premiers exemples) :";
        int count <- 0;
        loop trip_id over: tripId_to_route_index_majoritaire.keys {
            write "Trip " + trip_id + " → route index " + tripId_to_route_index_majoritaire[trip_id];
            count <- count + 1;
            if (count >= 10) { break; }
        }
        write "Total mappings créés : " + length(tripId_to_route_index_majoritaire);
    }

    action process_stops {
        write "Matching spatial des arrêts...";
        int n <- length(bus_stop);
        int current <- 0;
        nb_stops_matched <- 0;
        nb_stops_unmatched <- 0;
        
        loop while: (current < n) {
            int max_idx <- min(current + batch_size - 1, n - 1);
            list<bus_stop> batch <- bus_stop where (each.index >= current and each.index <= max_idx);
            
            loop s over: batch {
                do process_stop(s);
            }
            current <- max_idx + 1;
        }
        
        write "Matching terminé : " + nb_stops_matched + "/" + n + " arrêts associés";
    }

    action process_stop(bus_stop s) {
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
        network_route best_route <- nil;
    
        // Première passe (avec filtre de zones)
        loop radius over: search_radii {
            list<network_route> candidate_routes <- network_route where (
                (each.routeType_num = s.routeType) and (each.zone_id in neighbor_zone_ids)
            );
            if !empty(candidate_routes) {
                loop route over: candidate_routes {
                    float dist <- s distance_to route.shape;
                    if dist < best_dist {
                        best_dist <- dist;
                        best_route <- route;
                    }
                }
                if best_route != nil and best_dist <= radius {
                    s.closest_route_id <- best_route.osm_id;
                    s.closest_route_index <- best_route.index;
                    s.closest_route_dist <- best_dist;
                    s.is_matched <- true;
                    nb_stops_matched <- nb_stops_matched + 1;
                    found <- true;
                    break;
                }
            }
        }
        
        // 2e passe sans filtre de zones
        if !found {
            float best_dist2 <- #max_float;
            network_route best_route2 <- nil;
            loop radius over: search_radii {
                list<network_route> candidate_routes2 <- network_route where (
                    each.routeType_num = s.routeType
                );
                if !empty(candidate_routes2) {
                    loop route2 over: candidate_routes2 {
                        float dist2 <- s distance_to route2.shape;
                        if dist2 < best_dist2 {
                            best_dist2 <- dist2;
                            best_route2 <- route2;
                        }
                    }
                    if best_route2 != nil and best_dist2 <= radius {
                        s.closest_route_id <- best_route2.osm_id;
                        s.closest_route_index <- best_route2.index;
                        s.closest_route_dist <- best_dist2;
                        s.is_matched <- true;
                        nb_stops_matched <- nb_stops_matched + 1;
                        found <- true;
                        break;
                    }
                }
            }
        }

        // Si toujours rien trouvé
        if !found {
            float best_dist3 <- #max_float;
            network_route best_route3 <- nil;
            list<network_route> all_routes <- network_route where (each.routeType_num = s.routeType);
            loop route3 over: all_routes {
                float dist3 <- s distance_to route3.shape;
                if dist3 < best_dist3 {
                    best_dist3 <- dist3;
                    best_route3 <- route3;
                }
            }
            if best_route3 != nil {
                s.closest_route_id <- best_route3.osm_id;
                s.closest_route_index <- best_route3.index;
                s.closest_route_dist <- best_dist3;
                s.is_matched <- false;
                nb_stops_unmatched <- nb_stops_unmatched + 1;
            } else {
                do reset_stop(s);
            }
        }
    }

    action reset_stop(bus_stop s) {
        s.closest_route_id <- "";
        s.closest_route_index <- -1;
        s.closest_route_dist <- -1.0;
        s.is_matched <- false;
        nb_stops_unmatched <- nb_stops_unmatched + 1;
    }
    
    // === NOUVELLES ACTIONS POUR LA SIMULATION ===
    
    action prepare_simulation {
    write "Préparation de la simulation...";
    
    if !(tripId_to_route_index_majoritaire contains_key selected_trip_id) {
        write "ERREUR : Trip " + selected_trip_id + " non trouvé dans le mapping !";
        return;
    }
    
    selected_route_index <- tripId_to_route_index_majoritaire[selected_trip_id];
    write "Route index sélectionnée : " + selected_route_index;
    
    network_route selected_route <- network_route[selected_route_index];
    if selected_route = nil {
        write "ERREUR : Route avec index " + selected_route_index + " non trouvée !";
        return;
    }
    
    // AMÉLIORATION : Créer un graphe plus robuste
    list<geometry> route_segments <- [];
    
    // Récupérer toutes les routes compatibles (même type de transport)
    list<network_route> compatible_routes <- network_route where (
        each.routeType_num = selected_route.routeType_num
    );
    
    // Ajouter les géométries des routes compatibles
    loop route over: compatible_routes {
        if route.shape != nil and length(route.shape.points) > 1 {
            route_segments <+ route.shape;
        }
    }
    
    // Créer le graphe avec toutes les routes compatibles
    if !empty(route_segments) {
        route_network <- as_edge_graph(route_segments);
        write "Graphe créé avec " + length(route_segments) + " segments de route";
    } else {
        // Fallback : utiliser seulement la route sélectionnée
        route_network <- as_edge_graph([selected_route.shape]);
        write "Graphe créé avec la route sélectionnée uniquement";
    }
    
    // Reste du code inchangé...
    if selected_stop_index >= 0 and selected_stop_index < length(bus_stop) {
        starts_stop <- bus_stop[selected_stop_index];
    } else {
        write "ERREUR : Index d'arrêt " + selected_stop_index + " invalide !";
        return;
    }
    
    if !(starts_stop.departureStopsInfo contains_key selected_trip_id) {
        write "ERREUR : L'arrêt sélectionné n'a pas d'info pour le trip " + selected_trip_id;
        return;
    }
    
    list<pair<bus_stop, string>> stops_for_trip <- starts_stop.departureStopsInfo[selected_trip_id];
    trip_bus_stops <- stops_for_trip collect (each.key);
    
    ask bus_stop {
        is_on_selected_trip <- false;
    }
    ask trip_bus_stops {
        is_on_selected_trip <- true;
    }
    
    write "Arrêts du trip préparés : " + length(trip_bus_stops);
}
    
    action launch_bus_simulation {
        if trip_bus_stops = nil or empty(trip_bus_stops) {
            write "ERREUR : Aucun arrêt trouvé pour la simulation !";
            return;
        }
        
        if length(trip_bus_stops) < 2 {
            write "ERREUR : Au moins 2 arrêts nécessaires pour la simulation !";
            return;
        }
        
        list<pair<bus_stop, string>> stops_for_trip <- starts_stop.departureStopsInfo[selected_trip_id];
        
        create bus with: [
            my_departureStopsInfo:: stops_for_trip,
            current_stop_index:: 0,
            location:: trip_bus_stops[0].location,
            target_location:: trip_bus_stops[1].location,
            start_time:: int(cycle * step / #s)
        ];
        
        write "Bus créé et simulation lancée !";
    }
}

species bus_stop skills: [TransportStopSkill] {
    // Attributs de matching
    string closest_route_id <- "";
    int closest_route_index <- -1;
    float closest_route_dist <- -1.0;
    int zone_id;
    bool is_matched <- false;
    
    // Attributs de simulation
    rgb customColor <- rgb(0,0,255);
    string name;
    bool is_on_selected_trip <- false;
    map<string, map<string, list<string>>> departureStopsInfo;

    aspect base {
        rgb color <- is_matched ? #blue : #red;
        if is_on_selected_trip {
            color <- #yellow;
        }
        draw circle(100.0) color: color;
        
        if (is_on_selected_trip and name != nil) {
            draw name color: #black font: font("Arial", 10, #bold) at: location + {0, 120};
        }
    }
    
    aspect detailed {
        rgb color <- is_matched ? #blue : #red;
        if is_on_selected_trip {
            color <- #yellow;
        }
        draw circle(100.0) color: color;
        if !is_matched {
            draw "Type: " + routeType color: #black size: 8 at: location + {0,0,5};
        }
    }
}

species network_route {
    geometry shape;
    string route_type;
    int routeType_num;
    string name;
    string osm_id;
    int zone_id;
    
    aspect base {
        rgb color <- #green;
        if index = selected_route_index {
            color <- #orange;
        }
        draw shape color: color width: 2;
    }
}

species bus skills: [moving] {
    list<pair<bus_stop, string>> my_departureStopsInfo;
    int current_stop_index <- 0;
    point target_location;
    bool has_arrived <- false;
    int start_time;
    
    // AMÉLIORATION : Vitesse plus réaliste et gestion du mouvement
    float speed <- 30.0 #km/#h;  // Vitesse plus réaliste pour un bus urbain
    float tolerance <- 20.0 #m;  // Distance de tolérance pour "arriver" à un arrêt
    bool is_moving <- false;
    path current_path;

    init {
        write "Bus créé avec " + length(my_departureStopsInfo) + " arrêts";
        // Calculer le premier chemin
        do calculate_path_to_target;
    }

    // ACTION : Calculer le chemin vers la cible
    action calculate_path_to_target {
        if target_location != nil and route_network != nil {
            current_path <- path_between(route_network, location, target_location);
            if current_path != nil {
                write "Chemin calculé vers " + my_departureStopsInfo[current_stop_index].key.name;
                is_moving <- true;
            } else {
                write "ATTENTION : Pas de chemin trouvé, déplacement direct";
                is_moving <- true;
            }
        }
    }

    aspect base {
        // Dessiner le bus avec une orientation basée sur la direction
        draw rectangle(200, 100) color: #red rotate: heading;
        
        // Optionnel : dessiner le chemin prévu
        if current_path != nil {
            draw current_path.shape color: #blue width: 3;
        }
    }

    // AMÉLIORATION : Mouvement plus fluide
    reflex move when: is_moving and target_location != nil {
        float dist_to_target <- self.location distance_to target_location;
        
        if dist_to_target > tolerance {
            if current_path != nil and current_path.shape != nil {
                // Suivre le chemin calculé
                do follow path: current_path speed: speed;
            } else {
                // Mouvement direct si pas de chemin
                do goto target: target_location speed: speed;
            }
        } else {
            // Arrivé à destination
            location <- target_location;
            is_moving <- false;
            do arrive_at_stop;
        }
    }

    // ACTION : Gérer l'arrivée à un arrêt
    action arrive_at_stop {
        string stop_name <- my_departureStopsInfo[current_stop_index].key.name;
        write "Bus arrivé à l'arrêt : " + stop_name + " (index: " + current_stop_index + ")";
        
        if (current_stop_index < length(my_departureStopsInfo) - 1) {
            current_stop_index <- current_stop_index + 1;
            target_location <- my_departureStopsInfo[current_stop_index].key.location;
            
            string next_stop_name <- my_departureStopsInfo[current_stop_index].key.name;
            write "Bus se dirige vers : " + next_stop_name;
            
            // Recalculer le chemin vers le prochain arrêt
            do calculate_path_to_target;
        } else {
            write "Bus arrivé au terminus !";
            has_arrived <- true;
            do die;
        }
    }
   }

experiment main type: gui {
    output {
        display map {
            species network_route aspect: base;
            species bus_stop aspect: base;
            species bus aspect: base;
            
            overlay position: {10, 10} size: {300 #px, 160 #px} background: #white transparency: 0.7 {
                draw "=== STATISTIQUES ===" at: {20#px, 20#px} color: #black font: font("SansSerif", 12, #bold);
                draw "Trips mappés : " + length(tripId_to_route_index_majoritaire) at: {20#px, 40#px} color: #black;
                draw "Arrêts associés : " + nb_stops_matched + "/" + nb_total_stops at: {20#px, 60#px} color: #blue;
                draw "Non associés : " + nb_stops_unmatched at: {20#px, 80#px} color: #red;
                draw "=== SIMULATION ===" at: {20#px, 100#px} color: #black font: font("SansSerif", 12, #bold);
                draw "Trip sélectionné : " + selected_trip_id at: {20#px, 120#px} color: #black;
                draw "Route index : " + selected_route_index at: {20#px, 140#px} color: #orange;
            }
        }
    }
}