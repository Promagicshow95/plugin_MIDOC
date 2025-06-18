/**
* Name: associer_tripId_osmId
* Author: Promagicshow95
* Description: Lier chaque tripId GTFS à un seul osm_id OSM (shape majoritaire)
* Tags: GTFS, OSM, mapping, transport
* Date: 2025-06-13 14:11:41
*/

model associer_tripId_osmId

global {
    // --- PARAMÈTRES ---
    int grid_size <- 300;
    list<float> search_radii <- [500.0, 1000.0, 1500.0]; // tu peux ajuster ces valeurs
    int batch_size <- 500;

    // --- FICHIERS ---
    point top_left <- CRS_transform({0,0}, "EPSG:4326").location;
    point bottom_right <- CRS_transform({shape.width, shape.height}, "EPSG:4326").location;
    string adress <- "http://overpass-api.de/api/xapi_meta?*[bbox=" + top_left.x + "," + bottom_right.y + "," + bottom_right.x + "," + top_left.y + "]";
    //file<geometry> osm_geometries <- osm_file<geometry>(adress, osm_data_to_generate);
    file<geometry> osm_geometries <- osm_file("../../includes/Hanoi_map.osm", osm_data_to_generate);
    gtfs_file gtfs_f <- gtfs_file("../../includes/filtered_gtfs");
    file data_file <- shape_file("../../includes/stops_points_wgs84.shp");
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

    // --- MAPPING FINAL ---
    map<string, string> tripId_to_osm_id_majoritaire <- [];

    init {
        write "=== Initialisation du modèle ===";
        
        // --- Création des arrêts GTFS et récupération des types ---
        create bus_stop from: gtfs_f;
        nb_total_stops <- length(bus_stop);
        route_types_gtfs <- bus_stop collect(each.routeType) as list<int>;
        route_types_gtfs <- remove_duplicates(route_types_gtfs);
        
        write "Types de transport GTFS trouvés : " + route_types_gtfs;
        
        // --- Création des network_route OSM ---
        do create_network_routes;
        
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
        
        // Étape 1 : Collecter les osm_id pour chaque trip
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
        
        // Étape 2 : Déterminer l'osm_id majoritaire pour chaque trip
        loop trip_id over: temp_mapping.keys {
            list<string> osm_ids <- temp_mapping[trip_id];
            map<string, int> counter <- [];
            
            // Compter les occurrences
            loop osm_id over: osm_ids {
                counter[osm_id] <- (counter contains_key osm_id) ? counter[osm_id] + 1 : 1;
            }
            
            // Trouver le plus fréquent
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
        
        // Affichage des résultats
        write "\nRésultats du mapping (10 premiers exemples) :";
        int count <- 0;
        loop trip_id over: tripId_to_osm_id_majoritaire.keys {
            write "Trip " + trip_id + " → OSM " + tripId_to_osm_id_majoritaire[trip_id];
            count <- count + 1;
            if (count >= 10) { break; }
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
    
    // ==== Première passe (avec filtre de zones) ====
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
    
    // ==== 2e passe sans filtre de zones, si toujours non associé ====
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

    // ==== Si toujours rien trouvé, log le plus proche globalement ou reset ====
    if !found {
        // Log le plus proche globalement, même hors rayon
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
            s.is_matched <- false; // toujours non matché "officiellement"
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
    

    
    aspect base {
        draw shape color: #green;
    }
}

experiment main type: gui {
    
    
    output {
        display map {
            species network_route aspect: base;
            species bus_stop aspect: base;
            
            overlay position: {10, 10} size: {250 #px, 120 #px} background: #white transparency: 0.7 {
                draw "Statistiques" at: {20#px, 20#px} color: #black font: font("SansSerif", 14, #bold);
                draw "Trips mappés : " + length(tripId_to_osm_id_majoritaire) at: {20#px, 40#px} color: #black;
                draw "Arrêts associés : " + nb_stops_matched + "/" + nb_total_stops at: {20#px, 60#px} color: #blue;
                draw "Non associés : " + nb_stops_unmatched at: {20#px, 80#px} color: #red;
            }
        }
        

    }
}