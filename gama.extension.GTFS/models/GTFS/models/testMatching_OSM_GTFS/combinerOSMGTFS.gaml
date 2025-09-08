/**
* Name: associer_tripId_osmId_updated
* Author: Promagicshow95
* Description: Version avec logique réseau mise à jour de ReseauxOSM_Hanoi
* Tags: GTFS, OSM, mapping, transport
* Date: 2025-08-13
*/

model associer_tripId_osmId_updated

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
    gtfs_file gtfs_f <- gtfs_file("../../includes/hanoi_gtfs_pm");
    file data_file <- shape_file("../../includes/shapeFileHanoishp.shp");
    geometry shape <- envelope(data_file);

    // --- FILTRES OSM (COMPLET COMME RESEAUOSM_HANOI) ---
    map<string, list> osm_data_to_generate <- [
        "highway"::[],     // TOUTES les routes
        "railway"::[],     // TOUTES les voies ferrées  
        "route"::[],       // TOUTES les relations route
        "cycleway"::[]     // TOUTES les pistes cyclables
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

    // --- VARIABLES STATISTIQUES (COMME RESEAUOSM_HANOI) ---
    int nb_bus_routes <- 0;
    int nb_tram_routes <- 0;
    int nb_metro_routes <- 0;
    int nb_train_routes <- 0;
    int nb_cycleway_routes <- 0;
    int nb_road_routes <- 0;
    int nb_other_routes <- 0;

    // --- Variables pour analyser la connectivité ---
    map<int, int> route_counts <- [];
    map<int, int> unique_points_per_type <- [];

    // --- MAPPING FINAL ---
    map<string, string> tripId_to_osm_id_majoritaire <- [];

    init {
        write "=== Initialisation du modèle avec réseau mis à jour ===";
        
        // --- Création des arrêts GTFS ---
        create bus_stop from: gtfs_f;
        nb_total_stops <- length(bus_stop);
        route_types_gtfs <- bus_stop collect(each.routeType) as list<int>;
        route_types_gtfs <- remove_duplicates(route_types_gtfs);
        
        write "Types de transport GTFS trouvés : " + route_types_gtfs;
        
        // --- Création des routes OSM (LOGIQUE COMPLÈTE DE RESEAUOSM_HANOI) ---
        do create_network_routes_complete;
        
        // --- Analyser la connectivité ---
        do analyze_simple_connectivity;
        
        // --- Assignation des zones ---
        do assign_zones;
        
        // --- Matching spatial (avec cohérence routeType) ---
        do process_stops;
        
        // --- Création du mapping tripId → osm_id ---
        do create_trip_mapping;
    }
    
    // ✅ LOGIQUE COMPLÈTE DE RESEAUOSM_HANOI (SANS FILTRE GTFS)
    action create_network_routes_complete {
        write "=== CRÉATION RÉSEAU COMPLET (ReseauxOSM_Hanoi) ===";
        
        write "Géométries OSM chargées : " + length(osm_geometries);
        
        // Création des routes avec MÊME LOGIQUE que ReseauxOSM_Hanoi
        loop geom over: osm_geometries {
            if length(geom.points) > 1 {
                do create_single_route_complete(geom);
            }
        }
        
        // Statistiques finales
        write "\n=== RÉSEAU CRÉÉ (IDENTIQUE RESEAUOSM_HANOI) ===";
        write "🚌 Routes Bus : " + nb_bus_routes;
        write "🚋 Routes Tram : " + nb_tram_routes; 
        write "🚇 Routes Métro : " + nb_metro_routes;
        write "🚂 Routes Train : " + nb_train_routes;
        write "🚴 Routes Cycleway : " + nb_cycleway_routes;
        write "🛣️ Routes Road : " + nb_road_routes;
        write "❓ Autres : " + nb_other_routes;
        write "🛤️ TOTAL : " + length(network_route);
    }
    
    // ✅ LOGIQUE EXACTE DU MODÈLE RESEAUOSM_HANOI
    action create_single_route_complete(geometry geom) {
        string route_type;
        int routeType_num;
        rgb route_color;
        float route_width;
        string name <- (geom.attributes["name"] as string);
        string osm_id <- (geom.attributes["osm_id"] as string);

        // ✅ CLASSIFICATION IDENTIQUE À RESEAUOSM_HANOI
        if ((geom.attributes["gama_bus_line"] != nil) 
            or (geom.attributes["route"] = "bus") 
            or (geom.attributes["highway"] = "busway")) {
            route_type <- "bus";
            routeType_num <- 3;
            route_color <- #blue;
            route_width <- 2.0;
            nb_bus_routes <- nb_bus_routes + 1;
            
        } else if geom.attributes["railway"] = "tram" {
            route_type <- "tram";
            routeType_num <- 0;
            route_color <- #orange;
            route_width <- 3.0;
            nb_tram_routes <- nb_tram_routes + 1;
            
        } else if (
            geom.attributes["railway"] = "subway" or
            geom.attributes["route"] = "subway" or
            geom.attributes["route_master"] = "subway" or
            geom.attributes["railway"] = "metro" or
            geom.attributes["route"] = "metro"
        ) {
            route_type <- "subway";
            routeType_num <- 1;
            route_color <- #red;
            route_width <- 4.0;
            nb_metro_routes <- nb_metro_routes + 1;
            
        } else if geom.attributes["railway"] != nil 
                and !(geom.attributes["railway"] in ["abandoned", "platform", "disused"]) {
            route_type <- "railway";
            routeType_num <- 2;
            route_color <- #green;
            route_width <- 3.5;
            nb_train_routes <- nb_train_routes + 1;
            
        } else if (geom.attributes["cycleway"] != nil 
                or geom.attributes["highway"] = "cycleway") {
            route_type <- "cycleway";
            routeType_num <- 10;
            route_color <- #purple;
            route_width <- 1.5;
            nb_cycleway_routes <- nb_cycleway_routes + 1;
            
        } else if geom.attributes["highway"] != nil {
            route_type <- "road";
            routeType_num <- 20;
            route_color <- #gray;
            route_width <- 1.0;
            nb_road_routes <- nb_road_routes + 1;
            
        } else {
            route_type <- "other";
            routeType_num <- -1;
            route_color <- #black;
            route_width <- 0.5;
            nb_other_routes <- nb_other_routes + 1;
        }

        // ✅ CRÉER TOUTES LES ROUTES (comme ReseauxOSM_Hanoi, SANS FILTRE GTFS)
        if routeType_num != -1 {
            create network_route with: [
                shape::geom,
                route_type::route_type,
                routeType_num::routeType_num,
                route_color::route_color,
                route_width::route_width,
                name::name,
                osm_id::osm_id
            ];
        }
    }
    
    // --- Analyse simple de la connectivité (IDENTIQUE) ---
    action analyze_simple_connectivity {
        write "\n=== Analyse simple de la connectivité ===";
        
        // Ajouter les points de connectivité aux routes
        ask network_route {
            if shape != nil and length(shape.points) > 1 {
                start_point <- first(shape.points);
                end_point <- last(shape.points);
            }
        }
        
        // Analyser par type (TOUS LES TYPES, PAS SEULEMENT GTFS)
        list<int> all_route_types <- remove_duplicates(network_route collect(each.routeType_num));
        
        loop route_type over: all_route_types {
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
        write "Matching spatial des arrêts (avec cohérence routeType)...";
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

    // ✅ MATCHING AVEC COHÉRENCE ROUTETYPE (MÊME TYPE DE VÉHICULE)
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
            // ✅ COHÉRENCE ROUTETYPE : les deux doivent avoir le même type de véhicule
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
                // ✅ RECHERCHE GLOBALE AVEC COHÉRENCE ROUTETYPE
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

// ✅ ESPÈCE IDENTIQUE À RESEAUOSM_HANOI
species network_route {
    geometry shape;
    string route_type;
    int routeType_num;
    rgb route_color;
    float route_width;
    string name;
    string osm_id;
    int zone_id;
    
    // Points de connectivité
    point start_point;
    point end_point;
    
    aspect base {
        draw shape color: route_color width: route_width;
    }
    
    aspect detailed {
        draw shape color: route_color width: route_width;
        if name != nil {
            draw name color: #black size: 6 at: shape.location;
        }
    }
    
    aspect connectivity {
        draw shape color: route_color width: route_width;
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
            
            overlay position: {10, 10} size: {350 #px, 200 #px} background: #white transparency: 0.8 {
                draw "=== RÉSEAU COMPLET MISE À JOUR ===" at: {20#px, 20#px} color: #black font: font("Arial", 12, #bold);
                draw "🚌 Bus : " + nb_bus_routes + " routes" at: {20#px, 45#px} color: #blue;
                draw "🚋 Tram : " + nb_tram_routes + " routes" at: {20#px, 65#px} color: #orange;
                draw "🚇 Métro : " + nb_metro_routes + " routes" at: {20#px, 85#px} color: #red;
                draw "🚂 Train : " + nb_train_routes + " routes" at: {20#px, 105#px} color: #green;
                draw "🚴 Cycleway : " + nb_cycleway_routes + " routes" at: {20#px, 125#px} color: #purple;
                draw "🛣️ Roads : " + nb_road_routes + " routes" at: {20#px, 145#px} color: #gray;
                draw "🛤️ TOTAL : " + length(network_route) + " routes" at: {20#px, 165#px} color: #black font: font("Arial", 10, #bold);
                draw "Arrêts associés : " + nb_stops_matched + "/" + nb_total_stops at: {20#px, 185#px} color: #blue;
            }
        }
    }
}