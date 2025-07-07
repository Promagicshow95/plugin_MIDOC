/**
* Name: associer_tripId_osmId_working
* Author: Promagicshow95
* Description: Version qui marche - ton modèle original + analyse connectivité simple
* Tags: GTFS, OSM, mapping, transport
* Date: 2025-07-04
*/

model associer_tripId_osmId_working

global {
    // --- PARAMÈTRES ---
    int grid_size <- 300;
    list<float> search_radii <- [500.0, 1000.0, 1500.0];
    int batch_size <- 500;

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

    // --- VARIABLES ---
    list<int> route_types_gtfs;
    list<pair<int,int>> neighbors <- [
        {0,0}, {-1,0}, {1,0}, {0,-1}, {0,1},
        {-1,-1}, {-1,1}, {1,-1}, {1,1}
    ];

    int nb_total_stops <- 0;
    int nb_stops_matched <- 0;
    int nb_stops_unmatched <- 0;

    // --- NOUVEAU : Variables pour analyser la connectivité ---
    map<int, int> route_counts <- [];
    map<int, int> unique_points_per_type <- [];

    // --- MAPPING FINAL ---
    map<string, string> tripId_to_osm_id_majoritaire <- [];

    init {
        write "=== Initialisation du modèle fonctionnel ===";
        
        // --- Création des arrêts GTFS ---
        create bus_stop from: gtfs_f;
        nb_total_stops <- length(bus_stop);
        route_types_gtfs <- bus_stop collect(each.routeType) as list<int>;
        route_types_gtfs <- remove_duplicates(route_types_gtfs);
        
        write "Types de transport GTFS trouvés : " + route_types_gtfs;
        
        // --- Création des routes OSM (ton code original qui marche) ---
        do create_network_routes;
        
        // --- NOUVEAU : Analyser la connectivité simplement ---
        do analyze_simple_connectivity;
        
        // --- Assignation des zones ---
        do assign_zones;
        
        // --- Matching spatial ---
        do process_stops;
        
        // --- Création du mapping tripId → osm_id ---
        do create_trip_mapping;
    }
    
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
    
    // --- NOUVEAU : Analyse simple de la connectivité ---
    action analyze_simple_connectivity {
        write "\n=== Analyse simple de la connectivité ===";
        
        // Ajouter les points de connectivité aux routes
        ask network_route {
            if shape != nil and length(shape.points) > 1 {
                start_point <- first(shape.points);
                end_point <- last(shape.points);
            }
        }
        
        // Analyser par type
        loop route_type over: route_types_gtfs {
            list<network_route> routes <- network_route where (each.routeType_num = route_type);
            route_counts[route_type] <- length(routes);
            
            if !empty(routes) {
                // Collecter tous les points uniques pour ce type
                list<point> all_points <- [];
                ask routes {
                    if start_point != nil { all_points <+ start_point; }
                    if end_point != nil { all_points <+ end_point; }
                }
                
                list<point> unique_points <- remove_duplicates(all_points);
                unique_points_per_type[route_type] <- length(unique_points);
                
                write "Type " + route_type + " : " + length(routes) + " routes, " + length(unique_points) + " points uniques";
                
                // Estimation simple de connectivité
                if length(unique_points) > 0 {
                    float ratio <- length(routes) / length(unique_points);
                    if ratio > 0.8 {
                        write "✓ Type " + route_type + " : bien connecté (ratio = " + ratio + ")";
                    } else {
                        write "⚠ Type " + route_type + " : potentiellement fragmenté (ratio = " + ratio + ")";
                    }
                }
            } else {
                write "⚠ Type " + route_type + " : aucune route trouvée";
            }
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
        write "\nCréation du mapping tripId → osm_id...";
        
        map<string, list<string>> temp_mapping <- [];
        
        ask bus_stop where (each.is_matched) {
            loop trip_id over: departureStopsInfo.keys {
                if (temp_mapping contains_key trip_id) {
                    temp_mapping[trip_id] <+ closest_route_id;
                } else {
                    temp_mapping[trip_id] <- [closest_route_id];
                }
            }
        }
        
        loop trip_id over: temp_mapping.keys {
            list<string> osm_ids <- temp_mapping[trip_id];
            map<string, int> counter <- [];
            
            loop osm_id over: osm_ids {
                counter[osm_id] <- (counter contains_key osm_id) ? counter[osm_id] + 1 : 1;
            }
            
            string majority_osm_id;
            int max_count <- 0;
            
            loop osm_id over: counter.keys {
                if counter[osm_id] > max_count {
                    max_count <- counter[osm_id];
                    majority_osm_id <- osm_id;
                }
            }
            
            tripId_to_osm_id_majoritaire[trip_id] <- majority_osm_id;
        }
        
        write "Total mappings créés : " + length(tripId_to_osm_id_majoritaire);
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

        if !found {
            do reset_stop(s);
        }
    }

    action reset_stop(bus_stop s) {
        s.closest_route_id <- "";
        s.closest_route_index <- -1;
        s.closest_route_dist <- -1.0;
        s.is_matched <- false;
        nb_stops_unmatched <- nb_stops_unmatched + 1;
    }
}

species bus_stop skills: [TransportStopSkill] {
    string closest_route_id <- "";
    int closest_route_index <- -1;
    float closest_route_dist <- -1.0;
    int zone_id;
    bool is_matched <- false;
    map<string, map<string, list<string>>> departureStopsInfo;

    aspect base {
        draw circle(100.0) color: is_matched ? #blue : #red;
    }
    
    aspect detailed {
        draw circle(100.0) color: is_matched ? #blue : #red;
        if !is_matched {
            draw "Type: " + routeType color: #black size: 10 at: location + {0,0,5};
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
    
    // NOUVEAU : Points de connectivité
    point start_point;
    point end_point;
    
    // Couleur selon le type de transport
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
    
    aspect detailed {
        draw shape color: get_transport_color() width: 3;
        if name != nil {
            draw name color: #black size: 6 at: shape.location;
        }
    }
    
    aspect connectivity {
        draw shape color: get_transport_color() width: 2;
        if start_point != nil {
            draw circle(5) color: #yellow at: start_point;
        }
        if end_point != nil {
            draw circle(5) color: #red at: end_point;
        }
    }
}

experiment main type: gui {
    output {
        display map {
            species network_route aspect: base;
            species bus_stop aspect: base;
            
            overlay position: {10, 10} size: {300 #px, 140 #px} background: #white transparency: 0.7 {
                draw "Réseau de Transport Connecté" at: {20#px, 20#px} color: #black font: font("SansSerif", 14, #bold);
                draw "Routes : " + length(network_route) at: {20#px, 40#px} color: #green;
                draw "Trips mappés : " + length(tripId_to_osm_id_majoritaire) at: {20#px, 60#px} color: #black;
                draw "Arrêts associés : " + nb_stops_matched + "/" + nb_total_stops at: {20#px, 80#px} color: #blue;
                draw "Non associés : " + nb_stops_unmatched at: {20#px, 100#px} color: #red;
                
                // Stats de connectivité
                int y_pos <- 120;
                loop route_type over: route_counts.keys {
                    int routes <- route_counts[route_type];
                    int points <- unique_points_per_type[route_type];
                    if routes > 0 and points > 0 {
                        float ratio <- routes / points;
                        string status <- (ratio > 0.8) ? "✓" : "⚠";
                        draw "Type " + route_type + ": " + status at: {20#px, y_pos#px} color: (ratio > 0.8) ? #green : #orange;
                    }
                }
            }
        }
    }
}