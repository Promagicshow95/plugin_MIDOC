/**
 * Name: ReseauBus_Simulation_Complete
 * Author: Promagicshow95
 * Description: Modèle bus COMPLET avec tripShapeMap fonctionnel - SANS ERREURS
 * Tags: OSM, bus, simulation, network, GTFS, tripShapeMap
 * Date: 2025-08-20
 */

model ReseauBus_Simulation_Complete

global {
    // --- FICHIERS ---
    file data_file <- shape_file("../../includes/shapeFileHanoishp.shp");
    geometry shape <- envelope(data_file);
    
    // --- CONFIGURATION ---
    string target_crs;
    
    // --- BBOX POUR OVERPASS ---
    point top_left <- CRS_transform({0,0}, "EPSG:4326").location;
    point bottom_right <- CRS_transform({shape.width, shape.height}, "EPSG:4326").location;
    string bbox_str <- string(top_left.x) + "," + string(bottom_right.y) + "," + 
                       string(bottom_right.x) + "," + string(top_left.y);
    
    // 🔄 APPROCHE HYBRIDE : Bus + Routes de connectivité
    string xapi_base <- "http://overpass-api.de/api/xapi_meta?*[bbox=" + bbox_str + "]";
    
    // ✅ FILTRE HYBRIDE ÉQUILIBRÉ POUR SIMULATION
    map<string, list> osm_data_to_generate <- [
        // 🚌 INFRASTRUCTURE BUS
        "route"::["bus", "trolleybus"],                    // Relations bus
        "highway"::["busway"],                             // Voies dédiées bus
        "bus"::["yes", "designated"],                      // Routes avec accès bus
        "psv"::["yes"],                                    // Public service vehicle
        
        // 🛣️ ROUTES PRINCIPALES (connectivité)
        "highway"::["motorway", "trunk", "primary", "secondary", "tertiary"], // Routes principales
        
        // 🚋 TRANSPORT PUBLIC COMPLÉMENTAIRE
        "railway"::["tram", "subway", "metro", "rail"]     // Rails pour connectivité TC
    ];
    
    // --- VARIABLES ---
    int nb_total_stops <- 0;
    int nb_stops_matched <- 0;
    int nb_stops_unmatched <- 0;

    // --- FICHIERS GTFS ---
    gtfs_file gtfs_f <- gtfs_file("../../includes/hanoi_gtfs_pm");

    // --- STATISTIQUES ---
    int nb_bus_routes <- 0;
    int nb_connectivity_routes <- 0;
    int nb_tram_routes <- 0;
    int nb_metro_routes <- 0;
    int nb_train_routes <- 0;

    // 🆕 TRIPSHAPEMAP FINAL
    map<string, string> tripId_to_osm_id_majoritaire <- [];  // trip_id -> osm_id (vote majoritaire)

    init {
        write "=== RÉSEAU BUS POUR SIMULATION FINALE ===";
        
        // Récupération CRS
        target_crs <- crs(data_file);
        write "CRS du shapefile : " + target_crs;
        
        // 🚌 CRÉATION DES ARRÊTS GTFS (BUS UNIQUEMENT)
        write "🔄 Chargement des arrêts GTFS...";
        create bus_stop from: gtfs_f;
        write "Arrêts GTFS avant filtrage : " + length(bus_stop);
        
        // ✅ FILTRER : ne garder que les arrêts de bus (routeType = 3)
        ask bus_stop where (each.routeType != 3) { 
            do die; 
        }
        
        nb_total_stops <- length(bus_stop);
        write "✅ Arrêts de bus conservés : " + nb_total_stops;
        
        // 🔄 CHARGEMENT HYBRIDE
        write "🔄 Chargement réseau hybride (bus + connectivité)...";
        file<geometry> osm_geometries <- osm_file<geometry>(xapi_base, osm_data_to_generate);
        write "✅ Géométries chargées : " + length(osm_geometries);
        
        // 🚌 CRÉATION RÉSEAU HYBRIDE
        do create_hybrid_network(osm_geometries);
        
        // 🎯 MATCHING SPATIAL ARRÊTS ↔ ROUTES
        write "🔄 Assignation des zones spatiales...";
        do assign_zones;
        
        write "🔄 Matching spatial arrêts ↔ routes...";
        do process_stops;
        
        write "🔄 Création mapping tripId → osm_id avec vote majoritaire...";
        do create_trip_mapping_complete;
        
        // 📊 STATISTIQUES FINALES
        write "\n=== RÉSEAU HYBRIDE CRÉÉ ===";
        write "🚌 Routes Bus : " + nb_bus_routes;
        write "🛣️ Routes Connectivité : " + nb_connectivity_routes;
        write "🚋 Tram : " + nb_tram_routes;
        write "🚇 Métro : " + nb_metro_routes;
        write "🚂 Train : " + nb_train_routes;
        write "🛤️ TOTAL : " + length(network_route);
        write "🛑 ARRÊTS BUS : " + nb_total_stops;
        
        // Calcul ratio bus/total
        if length(network_route) > 0 {
            float bus_ratio <- nb_bus_routes / length(network_route) * 100;
            write "📊 Bus pur : " + (bus_ratio with_precision 1) + "%";
            write "📊 Connectivité : " + ((100 - bus_ratio) with_precision 1) + "%";
        }
        
        // 📊 STATISTIQUES TRIPSHAPEMAP
        write "\n=== TRIPSHAPEMAP FINALISÉ ===";
        do print_trip_shape_map_stats;
        do print_sample_trips;
        write "✅ Réseau prêt pour simulation de véhicules bus avec tripShapeMap";
    }
    
    // 🔄 CRÉATION RÉSEAU HYBRIDE INTELLIGENT
    action create_hybrid_network(file<geometry> osm_geoms) {
        write "=== Création réseau hybride connecté ===";
        
        loop geom over: osm_geoms {
            if (geom = nil or length(geom.points) <= 1) { 
                continue;
            }
            
            // 🎯 CLASSIFICATION PRIORITAIRE
            string route_type;
            int routeType_num;
            rgb route_color;
            float route_width;
            int priority;  // 1=bus prioritaire, 2=connectivité, 3=autres TC
            
            // 🚌 PRIORITÉ 1 : BUS (toujours créé)
            if (
                (geom.attributes["route"] in ["bus", "trolleybus"]) or
                (geom.attributes["route_master"] = "bus") or
                (geom.attributes["highway"] = "busway") or
                (geom.attributes["bus"] in ["yes", "designated"]) or
                (geom.attributes["psv"] = "yes") or
                (geom.attributes["gama_bus_line"] != nil)
            ) {
                route_type <- "bus";
                routeType_num <- 3;
                route_color <- #blue;
                route_width <- 3.0;
                priority <- 1;
                nb_bus_routes <- nb_bus_routes + 1;
                
            // 🚋 PRIORITÉ 2 : AUTRES TRANSPORTS PUBLICS
            } else if geom.attributes["railway"] = "tram" {
                route_type <- "tram";
                routeType_num <- 0;
                route_color <- #orange;
                route_width <- 2.5;
                priority <- 3;
                nb_tram_routes <- nb_tram_routes + 1;
                
            } else if (
                geom.attributes["railway"] = "subway" or
                geom.attributes["railway"] = "metro" or
                geom.attributes["route"] in ["subway", "metro"]
            ) {
                route_type <- "metro";
                routeType_num <- 1;
                route_color <- #red;
                route_width <- 2.5;
                priority <- 3;
                nb_metro_routes <- nb_metro_routes + 1;
                
            } else if geom.attributes["railway"] = "rail" {
                route_type <- "train";
                routeType_num <- 2;
                route_color <- #green;
                route_width <- 2.0;
                priority <- 3;
                nb_train_routes <- nb_train_routes + 1;
                
            // 🛣️ PRIORITÉ 3 : ROUTES DE CONNECTIVITÉ
            } else if geom.attributes["highway"] in ["motorway", "trunk", "primary", "secondary", "tertiary"] {
                route_type <- "connectivity";
                routeType_num <- 20;
                route_color <- #lightgray;
                route_width <- 1.2;
                priority <- 2;
                nb_connectivity_routes <- nb_connectivity_routes + 1;
                
            } else {
                continue; // Skip autres types
            }
            
            // 🗺️ REPROJECTION
            geometry geom_proj;
            if (target_crs != nil and target_crs != "" and target_crs != "EPSG:4326") {
                geom_proj <- CRS_transform(geom, "EPSG:4326", target_crs);
            } else {
                geom_proj <- geom;
            }
            
            // 📝 MÉTADONNÉES
            string name <- (geom.attributes["name"] as string);
            if (name = nil or name = "") {
                name <- (geom.attributes["ref"] as string);
            }
            if (name = nil or name = "") {
                if route_type = "bus" {
                    name <- "Bus Line " + (geom.attributes["osm_id"] as string);
                } else if route_type = "connectivity" {
                    name <- "Road " + (geom.attributes["highway"] as string);
                } else {
                    name <- route_type + " " + (geom.attributes["osm_id"] as string);
                }
            }
            
            // 🚌 CRÉATION AGENT
            create network_route with: [
                shape::geom_proj,
                route_type::route_type,
                routeType_num::routeType_num,
                route_color::route_color,
                route_width::route_width,
                name::name,
                osm_id::(geom.attributes["osm_id"] as string),
                priority::priority,
                length_m::geom_proj.perimeter
            ];
        }
        
        write "📊 Réseau hybride analysé :";
        write "  🚌 Bus pur : " + nb_bus_routes;
        write "  🛣️ Connectivité : " + nb_connectivity_routes;
        write "  🚋🚇🚂 Autres TC : " + (nb_tram_routes + nb_metro_routes + nb_train_routes);
    }
    
    // 🎯 ASSIGNATION ZONES SPATIALES (OPTIMISATION)
    action assign_zones {
        write "Attribution des zones spatiales (grille 300m)...";
        ask bus_stop {
            zone_id <- (int(location.x / 300) * 100000) + int(location.y / 300);
        }
        ask network_route {
            point centroid <- shape.location;
            zone_id <- (int(centroid.x / 300) * 100000) + int(centroid.y / 300);
        }
    }
    
    // 🎯 MATCHING SPATIAL OPTIMISÉ PAR BATCH
    action process_stops {
        write "Matching spatial des arrêts bus (cohérence de type)...";
        int n <- length(bus_stop);
        int current <- 0;
        nb_stops_matched <- 0;
        nb_stops_unmatched <- 0;
        
        loop while: (current < n) {
            int max_idx <- min(current + 500 - 1, n - 1);  // batch_size = 500
            list<bus_stop> batch <- bus_stop where (each.index >= current and each.index <= max_idx);
            
            loop s over: batch {
                do process_stop(s);
            }
            current <- max_idx + 1;
        }
        
        write "✅ Matching terminé : " + nb_stops_matched + "/" + n + " arrêts associés";
        write "❌ Non associés : " + nb_stops_unmatched + " arrêts";
    }

    // 🎯 MATCHING INTELLIGENT ARRÊT ↔ ROUTE (COHÉRENCE DE TYPE)
    action process_stop(bus_stop s) {
        int zx <- int(s.location.x / 300);  // grid_size = 300
        int zy <- int(s.location.y / 300);
        list<int> neighbor_zone_ids <- [];
        
        // Voisinage 3x3
        list<pair<int,int>> voisins <- [{0,0}, {-1,0}, {1,0}, {0,-1}, {0,1}, {-1,-1}, {-1,1}, {1,-1}, {1,1}];
        loop offset over: voisins {
            int nx <- zx + offset[0];
            int ny <- zy + offset[1];
            neighbor_zone_ids <+ (nx * 100000 + ny);
        }

        bool found <- false;
        float best_dist <- #max_float;
        network_route best_route <- nil;
        
        // Rayons de recherche
        list<float> rayons <- [500.0, 1000.0, 1500.0];
    
        // ✅ ÉTAPE 1 : Recherche routes MÊME TYPE dans zones voisines
        loop radius over: rayons {
            // COHÉRENCE STRICTE : routeType_num des routes = routeType des arrêts
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
        
        // ✅ ÉTAPE 2 : Fallback global - routes MÊME TYPE dans toute la zone
        if !found {
            float best_dist2 <- #max_float;
            network_route best_route2 <- nil;
            loop radius over: rayons {
                // TOUJOURS MÊME TYPE : bus_stop.routeType = network_route.routeType_num
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
        
        // ✅ ÉTAPE 3 : Dernier recours - routes de connectivité proches (pour continuité réseau)
        if !found {
            float best_dist3 <- #max_float;
            network_route best_route3 <- nil;
            float max_radius <- 200.0; // Rayon très court pour connectivité seulement
            
            list<network_route> connectivity_routes <- network_route where (
                (each.priority = 2) and (each.zone_id in neighbor_zone_ids) // Routes de connectivité
            );
            if !empty(connectivity_routes) {
                loop route3 over: connectivity_routes {
                    float dist3 <- s distance_to route3.shape;
                    if dist3 < best_dist3 and dist3 <= max_radius {
                        best_dist3 <- dist3;
                        best_route3 <- route3;
                    }
                }
                if best_route3 != nil {
                    s.closest_route_id <- best_route3.osm_id;
                    s.closest_route_index <- best_route3.index;
                    s.closest_route_dist <- best_dist3;
                    s.is_matched <- true;
                    nb_stops_matched <- nb_stops_matched + 1;
                    found <- true;
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
    
    // 🆕 CRÉATION MAPPING TRIPID → OSM_ID AVEC VOTE MAJORITAIRE (COMPLET)
    action create_trip_mapping_complete {
        write "Création du mapping tripId → osm_id avec vote majoritaire...";
        
        map<string, list<string>> temp_mapping <- [];
        int matched_stops <- 0;
        
        // ÉTAPE 1 : Collecter les osm_id par trip
        ask bus_stop where (each.is_matched) {
            matched_stops <- matched_stops + 1;
            loop trip_id over: departureStopsInfo.keys {
                if (temp_mapping contains_key trip_id) {
                    temp_mapping[trip_id] <+ closest_route_id;
                } else {
                    temp_mapping[trip_id] <- [closest_route_id];
                }
            }
        }
        
        write "📊 Données collectées pour " + length(temp_mapping) + " trips";
        
        // ÉTAPE 2 : VOTE MAJORITAIRE
        int trips_with_majority <- 0;
        int trips_without_majority <- 0;
        
        loop trip_id over: temp_mapping.keys {
            list<string> osm_ids <- temp_mapping[trip_id];
            
            if !empty(osm_ids) {
                // Compter les occurrences de chaque osm_id
                map<string, int> counter <- [];
                loop osm_id over: osm_ids {
                    counter[osm_id] <- (counter contains_key osm_id) ? counter[osm_id] + 1 : 1;
                }
                
                // Trouver l'osm_id majoritaire
                string majority_osm_id <- "";
                int max_count <- 0;
                
                loop osm_id over: counter.keys {
                    if counter[osm_id] > max_count {
                        max_count <- counter[osm_id];
                        majority_osm_id <- osm_id;
                    }
                }
                
                // Stocker le résultat
                if majority_osm_id != "" {
                    tripId_to_osm_id_majoritaire[trip_id] <- majority_osm_id;
                    trips_with_majority <- trips_with_majority + 1;
                } else {
                    trips_without_majority <- trips_without_majority + 1;
                }
            } else {
                trips_without_majority <- trips_without_majority + 1;
            }
        }
        
        // STATISTIQUES FINALES
        write "✅ TRIPSHAPEMAP CRÉÉ :";
        write "  📍 Arrêts avec mapping : " + matched_stops;
        write "  🎯 Trips avec vote majoritaire : " + trips_with_majority;
        write "  ❌ Trips sans majoritaire : " + trips_without_majority;
        write "  📊 Total mappings finaux : " + length(tripId_to_osm_id_majoritaire);
        
        // Analyse qualité du vote
        do analyze_trip_mapping_quality(temp_mapping);
    }
    
    // 🆕 ANALYSER LA QUALITÉ DU MAPPING
    action analyze_trip_mapping_quality(map<string, list<string>> temp_mapping) {
        write "\n=== ANALYSE QUALITÉ TRIPSHAPEMAP ===";
        
        int trips_single_route <- 0;
        int trips_multiple_routes <- 0;
        float total_confidence <- 0.0;
        list<float> confidences <- [];
        
        loop trip_id over: tripId_to_osm_id_majoritaire.keys {
            list<string> osm_ids <- temp_mapping[trip_id];
            string majority_osm_id <- tripId_to_osm_id_majoritaire[trip_id];
            
            // Calculer confiance du vote
            int majority_count <- 0;
            loop osm_id over: osm_ids {
                if osm_id = majority_osm_id {
                    majority_count <- majority_count + 1;
                }
            }
            
            float confidence <- length(osm_ids) > 0 ? (majority_count / length(osm_ids) * 100) : 0;
            confidences <+ confidence;
            total_confidence <- total_confidence + confidence;
            
            // Classer le trip
            int unique_routes <- length(remove_duplicates(osm_ids));
            if unique_routes = 1 {
                trips_single_route <- trips_single_route + 1;
            } else {
                trips_multiple_routes <- trips_multiple_routes + 1;
            }
        }
        
        // Statistiques globales
        float avg_confidence <- length(confidences) > 0 ? (total_confidence / length(confidences)) : 0;
        
        write "📊 Trips avec route unique : " + trips_single_route + " (" + 
              ((trips_single_route / length(tripId_to_osm_id_majoritaire)) * 100 with_precision 1) + "%)";
        write "📊 Trips multi-routes : " + trips_multiple_routes + " (" + 
              ((trips_multiple_routes / length(tripId_to_osm_id_majoritaire)) * 100 with_precision 1) + "%)";
        write "📊 Confiance moyenne du vote : " + (avg_confidence with_precision 1) + "%";
        
        // Analyser distribution confiance
        int high_confidence <- length(confidences where (each >= 80));
        int medium_confidence <- length(confidences where (each >= 50 and each < 80));
        int low_confidence <- length(confidences where (each < 50));
        
        write "📊 Confiance élevée (≥80%) : " + high_confidence + " trips";
        write "📊 Confiance moyenne (50-80%) : " + medium_confidence + " trips";
        write "📊 Confiance faible (<50%) : " + low_confidence + " trips";
    }
    
    // Statistiques sur le tripShapeMap
    action print_trip_shape_map_stats {
        if length(tripId_to_osm_id_majoritaire) > 0 {
            write "📊 Total trips avec shapes : " + length(tripId_to_osm_id_majoritaire);
            
            list<string> unique_shapes <- remove_duplicates(tripId_to_osm_id_majoritaire.values);
            write "📊 Total shapes uniques : " + length(unique_shapes);
            write "📊 Ratio trips/shapes : " + ((length(tripId_to_osm_id_majoritaire) / length(unique_shapes)) with_precision 2);
            
            // Shape la plus utilisée
            map<string, int> shape_usage <- [];
            loop trip_id over: tripId_to_osm_id_majoritaire.keys {
                string shape_id <- tripId_to_osm_id_majoritaire[trip_id];
                shape_usage[shape_id] <- (shape_usage contains_key shape_id) ? shape_usage[shape_id] + 1 : 1;
            }
            
            string most_used_shape <- "";
            int max_usage <- 0;
            loop shape_id over: shape_usage.keys {
                if shape_usage[shape_id] > max_usage {
                    max_usage <- shape_usage[shape_id];
                    most_used_shape <- shape_id;
                }
            }
            
            write "📊 Shape la plus utilisée : " + most_used_shape + " (" + max_usage + " trips)";
        } else {
            write "❌ Aucun tripShapeMap créé";
        }
    }
    
    // Exemples de trips disponibles
    action print_sample_trips {
        if length(tripId_to_osm_id_majoritaire) > 0 {
            write "\n=== EXEMPLES DE TRIPS DISPONIBLES ===";
            int count <- 0;
            loop trip_id over: tripId_to_osm_id_majoritaire.keys {
                if count < 5 {
                    string shape_id <- tripId_to_osm_id_majoritaire[trip_id];
                    write "Trip: " + trip_id + " → Shape: " + shape_id;
                    count <- count + 1;
                }
            }
            write "... et " + (length(tripId_to_osm_id_majoritaire) - 5) + " autres trips";
        }
    }
}

// 🚌 AGENT ARRÊTS BUS GTFS
species bus_stop skills: [TransportStopSkill] {
    string closest_route_id <- "";
    int closest_route_index <- -1;
    float closest_route_dist <- -1.0;
    int zone_id;
    bool is_matched <- false;
    map<string, map<string, list<string>>> departureStopsInfo;

    aspect base {
        draw circle(80.0) color: is_matched ? #blue : #red;
    }
    
    aspect detailed {
        draw circle(80.0) color: is_matched ? #blue : #red;
        if !is_matched {
            draw "Bus Stop" color: #black size: 8 at: location + {0,0,5};
        } else {
            draw "✓" color: #white size: 6 at: location;
        }
    }
    
    aspect large {
        draw circle(120.0) color: is_matched ? #blue : #red;
        draw (is_matched ? "✓BUS" : "BUS") color: #white size: 6 at: location;
    }
    
    aspect with_distance {
        draw circle(80.0) color: is_matched ? #blue : #red;
        if is_matched and closest_route_dist >= 0 {
            draw string(closest_route_dist with_precision 0) + "m" color: #black size: 6 at: location + {0,0,10};
        }
    }
}

// 🚌 AGENT ROUTE POUR SIMULATION
species network_route {
    geometry shape;
    string route_type;
    int routeType_num;
    rgb route_color;
    float route_width;
    string name;
    string osm_id;
    int priority;      // 1=bus, 2=connectivité, 3=autres
    float length_m;
    int zone_id;       // Zone spatiale pour optimisation matching
    
    // ✅ ASPECT OPTIMISÉ POUR SIMULATION
    aspect simulation {
        if priority = 1 {
            // Bus routes : épaisses et bien visibles
            draw shape color: route_color width: route_width;
        } else if priority = 2 {
            // Routes de connectivité : plus fines
            draw shape color: route_color width: (route_width * 0.6);
        } else {
            // Autres transports publics : visibles mais moins prononcés
            draw shape color: route_color width: (route_width * 0.8);
        }
    }
}

// 🚌 VÉHICULE BUS UTILISANT LE TRIPSHAPEMAP
species bus_vehicle skills: [moving] {
    string assigned_trip_id;
    geometry route_shape;
    list<point> route_points;
    int current_point_index <- 0;
    float speed <- 15.0 #km/#h;
    point target_point; // Point cible actuel
    
    // Initialiser un véhicule avec un trip
    action assign_trip(string trip_id) {
        assigned_trip_id <- trip_id;
        
        // Accès direct au mapping global
        if (tripId_to_osm_id_majoritaire contains_key trip_id) {
            string osm_id <- tripId_to_osm_id_majoritaire[trip_id];
            network_route route <- network_route first_with (each.osm_id = osm_id);
            if route != nil {
                route_shape <- route.shape;
            }
        }
        
        if route_shape != nil {
            route_points <- route_shape.points;
            if !empty(route_points) {
                location <- first(route_points);
                write "✅ Bus assigné au trip " + trip_id + " (" + length(route_points) + " points)";
            }
        } else {
            write "❌ Impossible d'assigner le trip " + trip_id + " : pas de shape trouvée";
            do die;
        }
    }
    
    // Mouvement le long de la route
    reflex move_along_route when: (route_points != nil and current_point_index < length(route_points)) {
        target_point <- route_points[current_point_index];
        do goto target: target_point speed: speed;
        
        if (location distance_to target_point) < 10 {
            current_point_index <- current_point_index + 1;
            if current_point_index >= length(route_points) {
                write "🏁 Bus " + assigned_trip_id + " a terminé son parcours";
                do die;
            }
        }
    }
    
    aspect default {
        if route_shape != nil {
            draw circle(100) color: #yellow border: #orange width: 2;
            draw assigned_trip_id color: #black size: 8 at: location + {0,0,10};
        }
    }
}

// 🚌 EXPÉRIMENT SIMPLE - AFFICHAGE CARTE SEULEMENT
experiment carte_simple type: gui {
    output {
        display "Réseau Bus - Carte Simple" background: #white {
            species network_route aspect: simulation;
            species bus_stop aspect: base;
        }
    }
}