model lierGTFSOSM

global {
    // --- PARAMÈTRES CONFIGURABLES ---
    int grid_size <- 300;        // Taille de la grille (en mètres)
    float search_radius <- 500.0; // Distance max de recherche (en mètres)
    int batch_size <- 500;       // Taille d'un lot pour le traitement batch

    point top_left <- CRS_transform({0,0}, "EPSG:4326").location;
    point bottom_right <- CRS_transform({shape.width, shape.height}, "EPSG:4326").location;
    string adress <- "http://overpass-api.de/api/xapi_meta?*[bbox=" + top_left.x + "," + bottom_right.y + "," + bottom_right.x + "," + top_left.y + "]";
    
    file<geometry> osm_geometries <- osm_file<geometry>(adress, osm_data_to_generate);
    gtfs_file gtfs_f <- gtfs_file("../../includes/hanoi_gtfs_pm");
    file data_file <- shape_file("../../includes/stops_points_wgs84.shp");
    geometry shape <- envelope(data_file);

    map<string, list> osm_data_to_generate <- [
        "highway"::[], 
        "railway"::[], 
        "route"::[], 
        "cycleway"::[]
    ];

    list<int> route_types_gtfs;
    list<pair<int,int>> neighbors <- [
        {0,0}, {-1,0}, {1,0}, {0,-1}, {0,1},
        {-1,-1}, {-1,1}, {1,-1}, {1,1}
    ];

    int nb_total_stops <- 0;
    int nb_stops_matched <- 0;
    int nb_stops_unmatched <- 0;

    init {
        // --- Création des bus_stop et récupération des types GTFS ---
        create bus_stop from: gtfs_f;
        nb_total_stops <- length(bus_stop);

        route_types_gtfs <- bus_stop collect(each.routeType) as list<int>;
        route_types_gtfs <- remove_duplicates(route_types_gtfs);

        // --- Création des network_route OSM filtrées ---
        loop geom over: osm_geometries {
            if length(geom.points) > 1 {
                string route_type;
                int routeType_num;
                string name <- (geom.attributes["name"] as string);
                string osm_id <- (geom.attributes["osm_id"] as string);

                if ((geom.attributes["gama_bus_line"] != nil) 
                    or (geom.attributes["route"] = "bus") 
                    or (geom.attributes["highway"] = "busway")) {
                    route_type <- "bus";
                    routeType_num <- 3;
                    if (geom.attributes["gama_bus_line"] != nil) {
                        name <- geom.attributes["gama_bus_line"] as string;
                    }
                } else if geom.attributes["railway"] = "tram" {
                    route_type <- "tram";
                    routeType_num <- 0;
                } else if geom.attributes["railway"] = "subway" {
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
        }

        // --- Affectation des zones (grid) ---
        ask bus_stop {
            zone_id <- (int(location.x / grid_size) * 100000) + int(location.y / grid_size);
        }
        
        ask network_route {
            point centroid <- shape.location;  // Remplace centroid_of
            zone_id <- (int(centroid.x / grid_size) * 100000) + int(centroid.y / grid_size);
        }

        // --- Traitement optimisé par lots ---
        do process_stops;
    }
    
    // Action séparée pour le traitement des stops
    action process_stops {
        int n <- length(bus_stop);
        int current <- 0;
        nb_stops_matched <- 0;
        nb_stops_unmatched <- 0;
        
        loop while: (current < n) {
            int max_idx <- min(current + batch_size - 1, n - 1);
            list<bus_stop> batch <- bus_stop where (each.index >= current and each.index <= max_idx);
            
            write "Traitement des arrêts " + current + " à " + max_idx + " / " + n;

            loop s over: batch {
                do process_stop(s);
            }
            
            write "Progression : " + (max_idx+1) + "/" + n + " stops traités, associés : " + nb_stops_matched + ", non associés : " + nb_stops_unmatched;
            current <- max_idx + 1;
        }
        
        write "Matching terminé. Arrêts associés : " + nb_stops_matched + " / " + n;
    }
    
    // Action pour traiter un seul stop
    action process_stop(bus_stop s) {
        int zx <- int(s.location.x / grid_size);
        int zy <- int(s.location.y / grid_size);
        list<int> neighbor_zone_ids <- [];
        
        loop offset over: neighbors {
            int nx <- zx + offset[0];
            int ny <- zy + offset[1];
            neighbor_zone_ids <+ (nx * 100000 + ny);
        }

        list<network_route> candidate_routes <- network_route where (
            (each.routeType_num = s.routeType) and (each.zone_id in neighbor_zone_ids)
        );

        if !empty(candidate_routes) {
            float min_dist <- #max_float;
            network_route nearest_route <- nil;
            
            loop route over: candidate_routes {
                float dist <- s distance_to route.shape;
                if dist < min_dist {
                    min_dist <- dist;
                    nearest_route <- route;
                }
            }
            
            if nearest_route != nil {
                s.closest_route_id <- nearest_route.osm_id;
                s.closest_route_index <- nearest_route.index;
                s.closest_route_dist <- min_dist;
                s.is_matched <- true;
                nb_stops_matched <- nb_stops_matched + 1;
            } else {
                do reset_stop(s);
            }
        } else {
            do reset_stop(s);
        }
    }
    
    // Action pour réinitialiser un stop non associé
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

    aspect base {
        draw circle(100.0) color: is_matched ? #blue : #red;
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
        }
      
    }
}