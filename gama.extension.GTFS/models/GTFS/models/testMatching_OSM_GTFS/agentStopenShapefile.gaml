/**
 * Name: Network_Bus_With_GTFS_Matching_Optimized
 * Author: Promagicshow95
 * Description: Réseau bus depuis shapefiles + matching optimisé GTFS-OSM + Export departureStopsInfo
 * Tags: shapefile, network, bus, gtfs, matching, optimized, departureStopsInfo
 * Date: 2025-08-25
 * 
 * FONCTIONNALITÉS:
 * - Chargement réseau bus depuis shapefiles OSM exportés
 * - Chargement arrêts GTFS
 * - Matching spatial optimisé arrêts ↔ routes (avec grille spatiale + cache)
 * - Création map tripId_to_osm_id_majoritaire
 * - ✅ EXPORT departureStopsInfo dans shapefile (format sérialisé)
 * - ✅ EXPORT departureStopsInfo JSON avec structure complète préservée
 * - Visualisation résultats matching
 */

model Network_Bus_With_GTFS_Matching_Optimized

global {
    // --- CONFIGURATION FICHIERS ---
    string results_folder <- "../../results/";
    string gtfs_folder <- "../../includes/hanoi_gtfs_pm";  // ✅ AJOUT GTFS
    
    // ✅ FICHIER DE RÉFÉRENCE POUR L'ENVELOPPE
    file data_file <- shape_file("../../includes/shapeFileHanoishp.shp");
    geometry shape <- envelope(data_file);
    
    // ✅ FICHIER GTFS
    gtfs_file gtfs_f <- gtfs_file(gtfs_folder);
    
    // --- VARIABLES STATISTIQUES RÉSEAU ---
    int total_bus_routes <- 0;
    
    // --- VARIABLES STATISTIQUES MATCHING ---
    int nb_total_stops <- 0;
    int nb_stops_matched <- 0;
    int nb_stops_unmatched <- 0;
    
    // --- PARAMÈTRES OPTIMISATION ---
    int grid_size <- 500;  // ✅ Grille spatiale optimisée (500m)
    list<float> search_radii <- [300.0, 600.0, 1000.0, 1500.0];  // ✅ Rayons croissants
    int batch_size <- 200;  // ✅ Traitement par batch
    float max_global_search_radius <- 2000.0;  // ✅ Limite recherche globale
    
    // --- OPTIMISATIONS CACHE ---
    map<string, float> distance_cache <- [];  // ✅ Cache distances calculées
    int cache_hits <- 0;
    int cache_misses <- 0;
    
    // --- ZONES VOISINES POUR OPTIMISATION ---
    list<pair<int,int>> neighbors <- [
        {0,0}, {-1,0}, {1,0}, {0,-1}, {0,1},
        {-1,-1}, {-1,1}, {1,-1}, {1,1}
    ];
    
    // --- MAPPING FINAL TRIPID → OSM_ID ---
    map<string, string> tripId_to_osm_id_majoritaire <- [];
    
    // --- STATISTIQUES MATCHING ---
    map<string, int> matching_stats <- [];
    
    // --- DOSSIER EXPORT ---
    string export_folder <- "../../results/stopReseau/";

    init {
        write "=== MODÈLE BUS + GTFS MATCHING + DEPARTUREINFO ===";
        
        // 🚌 ÉTAPE 1: CHARGEMENT RÉSEAU BUS DEPUIS SHAPEFILES
        do load_bus_network_robust;
        
        // 🚏 ÉTAPE 2: CHARGEMENT ARRÊTS GTFS
        do load_gtfs_stops;
        
        // 🌍 ÉTAPE 3: VALIDATION ENVELOPPE
        do validate_world_envelope;
        
        // 🔧 ÉTAPE 4: OPTIMISATION SPATIALE
        do assign_spatial_zones;
        
        // 🎯 ÉTAPE 5: MATCHING OPTIMISÉ STOPS ↔ ROUTES
        do process_stops_optimized;
        
        // 📊 ÉTAPE 6: CRÉATION MAPPING TRIPID → OSM_ID
        do create_trip_mapping;
        
        // 🆕 ÉTAPE 7: PRÉPARATION DONNÉES EXPORT (departureStopsInfo)
        do prepare_departure_info_for_export;
        
        // 📈 ÉTAPE 8: STATISTIQUES FINALES
        do display_final_statistics;
        
        // 📦 ÉTAPE 9: EXPORT AUTOMATIQUE DES RÉSULTATS 
        do export_all_matching_results;
    }
    
    // 🚌 CHARGEMENT RÉSEAU BUS (EXISTANT)
    action load_bus_network_robust {
        write "\n🚌 === CHARGEMENT RÉSEAU BUS (AUTO-DÉTECTION) ===";
        
        int bus_parts_loaded <- 0;
        int bus_routes_count <- 0;
        int i <- 0;
        bool continue_loading <- true;
        
        loop while: continue_loading and i < 30 {
            string filename <- results_folder + "bus_routes_part" + i + ".shp";
            
            try {
                file shape_file_bus <- shape_file(filename);
                
                create bus_route from: shape_file_bus with: [
                    route_name::string(read("name")),
                    osm_id::string(read("osm_id")),
                    route_type::string(read("route_type")),
                    highway_type::string(read("highway")),
                    length_meters::float(read("length_m"))
                ];
                
                int routes_in_file <- length(shape_file_bus);
                bus_routes_count <- bus_routes_count + routes_in_file;
                bus_parts_loaded <- bus_parts_loaded + 1;
                
                write "  ✅ Part " + i + " : " + routes_in_file + " routes";
                i <- i + 1;
                
            } catch {
                write "  ℹ️ Fin détection à part" + i + " (fichier non trouvé)";
                continue_loading <- false;
            }
        }
        
        total_bus_routes <- bus_routes_count;
        write "📊 TOTAL BUS : " + bus_routes_count + " routes en " + bus_parts_loaded + " fichiers";
    }
    
    // 🚏 CHARGEMENT ARRÊTS GTFS
    action load_gtfs_stops {
        write "\n🚏 === CHARGEMENT ARRÊTS GTFS ===";
        
        try {
            create bus_stop from: gtfs_f;
            nb_total_stops <- length(bus_stop);
            
            // Filtrer uniquement les arrêts de bus (routeType = 3)
            list<bus_stop> non_bus_stops <- bus_stop where (each.routeType != 3);
            ask non_bus_stops {
                do die;
            }
            
            nb_total_stops <- length(bus_stop);
            write "✅ Arrêts GTFS bus chargés : " + nb_total_stops;
            
            // Statistiques types de transport
            if nb_total_stops > 0 {
                list<int> route_types <- remove_duplicates(bus_stop collect(each.routeType));
                write "🔍 Types de transport trouvés : " + route_types;
            }
            
        } catch {
            write "❌ Erreur chargement GTFS : " + gtfs_folder;
            nb_total_stops <- 0;
        }
    }
    
    // 🔧 ASSIGNATION ZONES SPATIALES OPTIMISÉES
    action assign_spatial_zones {
        write "\n🔧 === ASSIGNATION ZONES SPATIALES ===";
        
        // Assigner zones aux arrêts
        ask bus_stop {
            zone_id <- int(location.x / grid_size) * 100000 + int(location.y / grid_size);
        }
        
        // Assigner zones aux routes (par centroïde)
        ask bus_route {
            if shape != nil {
                point centroid <- shape.location;
                zone_id <- int(centroid.x / grid_size) * 100000 + int(centroid.y / grid_size);
            }
        }
        
        // Statistiques zones
        list<int> stop_zones <- remove_duplicates(bus_stop collect(each.zone_id));
        list<int> route_zones <- remove_duplicates(bus_route collect(each.zone_id));
        
        write "📊 Zones avec arrêts : " + length(stop_zones);
        write "📊 Zones avec routes : " + length(route_zones);
        write "📊 Taille grille : " + grid_size + "m";
    }
    
    // 🎯 PROCESSING OPTIMISÉ DES ARRÊTS
    action process_stops_optimized {
        write "\n🎯 === MATCHING OPTIMISÉ STOPS ↔ ROUTES ===";
        
        int total_stops <- length(bus_stop);
        if total_stops = 0 {
            write "❌ Aucun arrêt à traiter";
            return;
        }
        
        nb_stops_matched <- 0;
        nb_stops_unmatched <- 0;
        cache_hits <- 0;
        cache_misses <- 0;
        
        // Traitement par batch pour optimiser les performances
        int current <- 0;
        int batch_number <- 1;
        
        loop while: (current < total_stops) {
            int max_idx <- min(current + batch_size - 1, total_stops - 1);
            list<bus_stop> batch <- bus_stop where (each.index >= current and each.index <= max_idx);
            
            write "  🔄 Batch " + batch_number + " : arrêts " + current + "-" + max_idx;
            
            loop s over: batch {
                do process_single_stop_optimized(s);
            }
            
            current <- max_idx + 1;
            batch_number <- batch_number + 1;
        }
        
        write "✅ Matching terminé : " + nb_stops_matched + "/" + total_stops + " arrêts associés";
        write "📊 Cache hits/misses : " + cache_hits + "/" + cache_misses + " (efficacité: " + int((cache_hits/(cache_hits + cache_misses)) * 100) + "%)";
    }
    
    // 🔍 PROCESSING OPTIMISÉ D'UN ARRÊT INDIVIDUEL
    action process_single_stop_optimized(bus_stop s) {
        // Calculer zones voisines
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
        bus_route best_route <- nil;
    
        // ✅ PHASE 1: RECHERCHE LOCALE OPTIMISÉE (zones voisines + cohérence type)
        loop radius over: search_radii {
            if found { break; }
            
            // ✅ COHÉRENCE TYPE: arrêt routeType=3 (bus) → route route_type="bus"
            list<bus_route> candidate_routes <- bus_route where (
                (each.route_type = "bus") and (each.zone_id in neighbor_zone_ids)
            );
            
            if !empty(candidate_routes) {
                loop route over: candidate_routes {
                    float dist <- get_cached_distance(s, route);
                    
                    if dist < best_dist and dist <= radius {
                        best_dist <- dist;
                        best_route <- route;
                    }
                }
                
                if best_route != nil and best_dist <= radius {
                    do assign_stop_to_route(s, best_route, best_dist);
                    found <- true;
                    break;
                }
            }
        }
        
        // ✅ PHASE 2: RECHERCHE GLOBALE LIMITÉE (fallback + cohérence type)
        if !found {
            loop radius over: search_radii {
                if found or radius > max_global_search_radius { break; }
                
                // ✅ COHÉRENCE TYPE: même vérification en recherche globale
                list<bus_route> global_candidates <- bus_route where (
                    (each.route_type = "bus") and ((each distance_to s.location) <= radius)
                );
                
                if !empty(global_candidates) {
                    loop route over: global_candidates {
                        float dist <- get_cached_distance(s, route);
                        
                        if dist < best_dist and dist <= radius {
                            best_dist <- dist;
                            best_route <- route;
                        }
                    }
                    
                    if best_route != nil and best_dist <= radius {
                        do assign_stop_to_route(s, best_route, best_dist);
                        found <- true;
                        break;
                    }
                }
            }
        }

        // ✅ PHASE 3: AUCUN MATCH TROUVÉ
        if !found {
            do reset_stop(s);
        }
    }
    
    // 🔧 CACHE OPTIMISÉ DES DISTANCES
    float get_cached_distance(bus_stop s, bus_route r) {
        string cache_key <- string(s.index) + "_" + string(r.index);
        
        if distance_cache contains_key cache_key {
            cache_hits <- cache_hits + 1;
            return distance_cache[cache_key];
        } else {
            cache_misses <- cache_misses + 1;
            float dist <- s distance_to r.shape;
            
            // Limiter taille du cache (LRU simple)
            if length(distance_cache) > 10000 {
                // Vider le cache quand il devient trop gros
                distance_cache <- [];
            }
            
            distance_cache[cache_key] <- dist;
            return dist;
        }
    }
    
    // ✅ ASSIGNATION ARRÊT → ROUTE
    action assign_stop_to_route(bus_stop s, bus_route r, float dist) {
        s.closest_route_id <- r.osm_id;
        s.closest_route_index <- r.index;
        s.closest_route_dist <- dist;
        s.is_matched <- true;
        nb_stops_matched <- nb_stops_matched + 1;
    }
    
    // ❌ RESET ARRÊT NON MATCHÉ
    action reset_stop(bus_stop s) {
        s.closest_route_id <- "";
        s.closest_route_index <- -1;
        s.closest_route_dist <- -1.0;
        s.is_matched <- false;
        nb_stops_unmatched <- nb_stops_unmatched + 1;
    }
    
    // 📊 CRÉATION MAPPING TRIPID → OSM_ID
    action create_trip_mapping {
        write "\n📊 === CRÉATION MAPPING TRIPID → OSM_ID ===";
        
        if nb_stops_matched = 0 {
            write "❌ Aucun arrêt matché - mapping impossible";
            return;
        }
        
        map<string, list<string>> temp_mapping <- [];
        
        // Collecter OSM_IDs par trip_id
        ask bus_stop where (each.is_matched) {
            // Dans GTFS, departureStopsInfo contient trip_id → stops info
            if departureStopsInfo != nil {
                loop trip_id over: departureStopsInfo.keys {
                    if (temp_mapping contains_key trip_id) {
                        temp_mapping[trip_id] <+ closest_route_id;
                    } else {
                        temp_mapping[trip_id] <- [closest_route_id];
                    }
                }
            }
        }
        
        write "🔍 Trips détectés : " + length(temp_mapping);
        
        // Calculer OSM_ID majoritaire par trip
        loop trip_id over: temp_mapping.keys {
            list<string> osm_ids <- temp_mapping[trip_id];
            map<string, int> counter <- [];
            
            // Compter fréquences
            loop osm_id over: osm_ids {
                counter[osm_id] <- (counter contains_key osm_id) ? counter[osm_id] + 1 : 1;
            }
            
            // Trouver majoritaire
            string majority_osm_id <- "";
            int max_count <- 0;
            
            loop osm_id over: counter.keys {
                if counter[osm_id] > max_count {
                    max_count <- counter[osm_id];
                    majority_osm_id <- osm_id;
                }
            }
            
            if majority_osm_id != "" {
                tripId_to_osm_id_majoritaire[trip_id] <- majority_osm_id;
            }
        }
        
        write "✅ Mappings créés : " + length(tripId_to_osm_id_majoritaire) + " trips → osm_id";
        
        // Statistiques qualité mapping
        if length(tripId_to_osm_id_majoritaire) > 0 {
            list<string> unique_osm_ids <- remove_duplicates(tripId_to_osm_id_majoritaire.values);
            write "📊 Routes OSM utilisées : " + length(unique_osm_ids);
            write "📊 Ratio trips/routes : " + (length(tripId_to_osm_id_majoritaire) / length(unique_osm_ids));
        }
    }
    
    // 🆕 PRÉPARATION DEPARTUREINFO POUR EXPORT
    action prepare_departure_info_for_export {
        write "\n🆕 === PRÉPARATION DEPARTUREINFO POUR EXPORT ===";
        
        int stops_with_info <- 0;
        int stops_without_info <- 0;
        int serialization_errors <- 0;
        
        ask bus_stop {
            // Préparer les attributs sérialisés
            do serialize_departure_info;
            
            if departure_info_json != nil and departure_info_json != "" {
                stops_with_info <- stops_with_info + 1;
            } else {
                stops_without_info <- stops_without_info + 1;
                if departureStopsInfo != nil {
                    serialization_errors <- serialization_errors + 1;
                }
            }
        }
        
        write "📊 Arrêts avec departureInfo : " + stops_with_info;
        write "📊 Arrêts sans departureInfo : " + stops_without_info;
        write "📊 Erreurs sérialisation : " + serialization_errors;
        write "✅ Préparation terminée";
    }
    
    // 📈 STATISTIQUES FINALES
    action display_final_statistics {
        write "\n📈 === STATISTIQUES FINALES ===";
        write "🚌 Routes Bus : " + total_bus_routes;
        write "🚏 Arrêts GTFS : " + nb_total_stops;
        write "✅ Matchés : " + nb_stops_matched + " (" + int((nb_stops_matched/nb_total_stops)*100) + "%)";
        write "❌ Non-matchés : " + nb_stops_unmatched + " (" + int((nb_stops_unmatched/nb_total_stops)*100) + "%)";
        write "🗺️ Trips mappés : " + length(tripId_to_osm_id_majoritaire);
        write "🚀 Cache efficacité : " + int((cache_hits/(cache_hits + cache_misses))*100) + "%";
        
        // ✅ Vérification cohérence types
        if length(bus_stop) > 0 {
            list<int> stop_types <- remove_duplicates(bus_stop collect(each.routeType));
            write "🔍 Types arrêts GTFS : " + stop_types + " (3=bus)";
        }
        if length(bus_route) > 0 {
            list<string> route_types <- remove_duplicates(bus_route collect(each.route_type));
            write "🔍 Types routes OSM : " + route_types;
        }
        write "✅ Matching avec cohérence de type activé";
        
        // Qualité du matching
        if nb_total_stops > 0 {
            float match_rate <- (nb_stops_matched / nb_total_stops) * 100;
            if match_rate >= 80 {
                write "🎯 EXCELLENTE qualité matching (" + int(match_rate) + "%)";
            } else if match_rate >= 60 {
                write "✅ BONNE qualité matching (" + int(match_rate) + "%)";
            } else {
                write "⚠️ Qualité matching à améliorer (" + int(match_rate) + "%)";
            }
        }
        
        // 🆕 Info departureStopsInfo
        int stops_with_departure_info <- length(bus_stop where (each.departure_info_json != nil and each.departure_info_json != ""));
        write "📋 Arrêts avec departureInfo : " + stops_with_departure_info + "/" + nb_total_stops;
    }
    
    // 🌍 VALIDATION ENVELOPPE (EXISTANT)
    action validate_world_envelope {
        write "\n🌍 === VALIDATION ENVELOPPE MONDE ===";
        
        if shape != nil {
            write "✅ Enveloppe définie depuis shapeFileHanoishp.shp";
            write "📏 Dimensions: " + shape.width + " x " + shape.height;
        } else {
            write "❌ PROBLÈME: Aucune enveloppe définie";
            do create_envelope_from_data;
        }
    }
    
    // 🔧 CRÉER ENVELOPPE À PARTIR DES DONNÉES
    action create_envelope_from_data {
        write "\n🔧 === CRÉATION ENVELOPPE DEPUIS DONNÉES ===";
        
        list<geometry> all_shapes <- [];
        
        loop route over: bus_route {
            if route.shape != nil {
                all_shapes <+ route.shape;
            }
        }
        
        if !empty(all_shapes) {
            geometry union_geom <- union(all_shapes);
            shape <- envelope(union_geom);
            write "✅ Enveloppe créée : " + shape.width + " x " + shape.height;
        } else {
            shape <- rectangle(100000, 100000) at_location {587500, -2320000};
            write "⚠️ Utilisation enveloppe par défaut";
        }
    }
    
    // 🔧 ACTIONS DE RECHARGEMENT
    action reload_network_and_matching {
        write "\n🔄 === RECHARGEMENT COMPLET ===";
        
        // Effacer agents existants
        ask bus_route { do die; }
        ask bus_stop { do die; }
        
        // Réinitialiser variables
        total_bus_routes <- 0;
        nb_total_stops <- 0;
        nb_stops_matched <- 0;
        nb_stops_unmatched <- 0;
        distance_cache <- [];
        tripId_to_osm_id_majoritaire <- [];
        
        // Recharger tout
        do load_bus_network_robust;
        do load_gtfs_stops;
        do assign_spatial_zones;
        do process_stops_optimized;
        do create_trip_mapping;
        do prepare_departure_info_for_export;
        do display_final_statistics;
        
        write "🔄 Rechargement complet terminé";
    }
    
    // 📦 === EXPORT STOPS GTFS AVEC DEPARTUREINFO ===
    
    // 🚏 EXPORT STOPS GTFS AVEC TOUS LES ATTRIBUTS + DEPARTUREINFO
    action export_gtfs_stops_complete {
        write "\n🚏 === EXPORT STOPS GTFS COMPLETS + DEPARTUREINFO ===";
        
        if empty(bus_stop) {
            write "❌ Aucun arrêt à exporter";
            return;
        }
        
        // Préparer attributs pour export (convertir types problématiques)
        ask bus_stop {
            // Convertir boolean en string
            is_matched_str <- is_matched ? "TRUE" : "FALSE";
            
            // Assurer que les IDs existent
            if stopId = nil or stopId = "" {
                stopId <- "stop_" + string(index);
            }
            if name = nil or name = "" {
                name <- stopName != nil ? stopName : ("Stop_" + string(index));
            }
            
            // Calculer qualité matching
            if !is_matched {
                match_quality <- "NONE";
            } else if closest_route_dist <= 300 {
                match_quality <- "EXCELLENT";
            } else if closest_route_dist <= 600 {
                match_quality <- "GOOD";
            } else {
                match_quality <- "POOR";
            }
        }
        
        list<bus_stop> all_stops <- list(bus_stop);
        string stops_filename <- export_folder + "gtfs_stops_complete.shp";
        bool export_success <- false;
        
        // ÉTAPE 1 : Export avec TOUS les attributs GTFS + matching + DEPARTUREINFO
        try {
            save all_stops to: stops_filename format: "shp" attributes: [
                "stopId"::stopId,
                "name"::name,
                "stopName"::stopName,
                "routeType"::routeType,
                "tripNumber"::tripNumber,
                "closest_id"::closest_route_id,
                "closest_idx"::closest_route_index,
                "distance"::closest_route_dist,
                "matched"::is_matched_str,
                "quality"::match_quality,
                "zone_id"::zone_id,
                "departure_json"::departure_info_json,        // 🆕 DEPARTUREINFO JSON
                "departure_trips"::departure_info_tripids,    // 🆕 LISTE TRIP_IDS
                "departure_count"::departure_info_count       // 🆕 NOMBRE DE TRIPS
            ];
            
            write "✅ EXPORT STOPS COMPLET + DEPARTUREINFO RÉUSSI : " + stops_filename;
            write "📊 " + length(all_stops) + " arrêts exportés avec tous attributs + departureStopsInfo";
            export_success <- true;
            
        } catch {
            write "❌ Erreur export complet + departureInfo - tentative attributs essentiels...";
        }
        
        // ÉTAPE 2 : Export essentiel + departureInfo simplifié si échec
        if !export_success {
            try {
                save all_stops to: stops_filename format: "shp" attributes: [
                    "stopId"::stopId,
                    "name"::name,
                    "routeType"::routeType,
                    "closest_id"::closest_route_id,
                    "distance"::closest_route_dist,
                    "matched"::is_matched_str,
                    "quality"::match_quality,
                    "departure_trips"::departure_info_tripids,    // 🆕 AU MOINS LES TRIP_IDS
                    "departure_count"::departure_info_count       // 🆕 NOMBRE DE TRIPS
                ];
                
                write "✅ EXPORT STOPS ESSENTIEL + DEPARTUREINFO RÉUSSI : " + stops_filename;
                export_success <- true;
                
            } catch {
                write "❌ Erreur export essentiel + departureInfo - tentative standard...";
            }
        }
        
        // ÉTAPE 3 : Export standard sans departureInfo si échec
        if !export_success {
            try {
                save all_stops to: stops_filename format: "shp" attributes: [
                    "stopId"::stopId,
                    "name"::name,
                    "routeType"::routeType,
                    "closest_id"::closest_route_id,
                    "distance"::closest_route_dist,
                    "matched"::is_matched_str,
                    "quality"::match_quality
                ];
                
                write "✅ EXPORT STOPS STANDARD (sans departureInfo) RÉUSSI : " + stops_filename;
                write "⚠️ departureStopsInfo non inclus - données trop volumineuses pour shapefile";
                
            } catch {
                write "❌ Erreur export standard - export géométrie seule...";
                save all_stops to: stops_filename format: "shp";
                write "✅ EXPORT STOPS GÉOMÉTRIE SEULE : " + stops_filename;
            }
        }
    }
    
    // 📊 EXPORT MAPPING TRIPID → OSM_ID (CSV)
    action export_trip_mapping_simple {
        write "\n📊 === EXPORT MAPPING TRIP → ROUTE ===";
        
        if empty(tripId_to_osm_id_majoritaire) {
            write "❌ Aucun mapping à exporter";
            return;
        }
        
        string csv_path <- export_folder + "trip_to_route_mapping.csv";
        
        try {
            string csv_content <- "trip_id,osm_id,route_name,stops_count\n";
            
            loop trip_id over: tripId_to_osm_id_majoritaire.keys {
                string osm_id <- tripId_to_osm_id_majoritaire[trip_id];
                
                // Trouver info route
                bus_route matched_route <- first(bus_route where (each.osm_id = osm_id));
                string route_name <- matched_route != nil ? matched_route.route_name : "Unknown";
                
                // Compter arrêts de ce trip
                int stops_count <- 0;
                ask bus_stop where (each.is_matched and each.closest_route_id = osm_id) {
                    if departureStopsInfo != nil and (departureStopsInfo contains_key trip_id) {
                        stops_count <- stops_count + 1;
                    }
                }
                
                // Nettoyer nom route
                if route_name = nil or route_name = "" {
                    route_name <- "Route_" + osm_id;
                }
                
                csv_content <- csv_content + "\"" + trip_id + "\",\"" + osm_id + "\",\"" + route_name + "\"," + stops_count + "\n";
            }
            
            save csv_content to: csv_path format: "text";
            write "✅ MAPPING CSV EXPORTÉ : " + csv_path;
            write "📊 " + length(tripId_to_osm_id_majoritaire) + " mappings trip → route";
            
        } catch {
            write "❌ Erreur export CSV mapping";
        }
    }
    
    // 🆕 EXPORT DEPARTUREINFO COMPLET AVEC STRUCTURE PRÉSERVÉE
    action export_departure_info_complete {
        write "\n🆕 === EXPORT DEPARTUREINFO COMPLET (STRUCTURE PRÉSERVÉE) ===";
        
        string json_path <- export_folder + "departure_stops_info_complete.json";
        
        try {
            string json_content <- "{\n  \"stops_departure_info\": [\n";
            bool first_stop <- true;
            int stops_exported <- 0;
            
            // Exporter seulement les arrêts ayant departureStopsInfo non vide
            ask bus_stop where (each.departureStopsInfo != nil and !empty(each.departureStopsInfo)) {
                if !first_stop {
                    json_content <- json_content + ",\n";
                }
                first_stop <- false;
                stops_exported <- stops_exported + 1;
                
                json_content <- json_content + "    {\n";
                json_content <- json_content + "      \"stopId\": \"" + stopId + "\",\n";
                json_content <- json_content + "      \"name\": \"" + (name != nil ? name : "") + "\",\n";
                json_content <- json_content + "      \"location\": [" + location.x + ", " + location.y + "],\n";
                json_content <- json_content + "      \"closest_route_id\": \"" + (closest_route_id != nil ? closest_route_id : "") + "\",\n";
                json_content <- json_content + "      \"is_matched\": " + (is_matched ? "true" : "false") + ",\n";
                
                // STRUCTURE COMPLÈTE : map<string, map<string, list<string>>> departureStopsInfo
                json_content <- json_content + "      \"departureStopsInfo\": {\n";
                
                bool first_trip <- true;
                loop trip_id over: departureStopsInfo.keys {
                    if !first_trip {
                        json_content <- json_content + ",\n";
                    }
                    first_trip <- false;
                    
                    // trip_id -> map<string, list<string>>
                    json_content <- json_content + "        \"" + trip_id + "\": {\n";
                    
                    map<string, list<string>> trip_stops_info <- departureStopsInfo[trip_id];
                    bool first_route <- true;
                    
                    loop route_key over: trip_stops_info.keys {
                        if !first_route {
                            json_content <- json_content + ",\n";
                        }
                        first_route <- false;
                        
                        // route_key -> list<string>
                        json_content <- json_content + "          \"" + route_key + "\": [";
                        
                        list<string> stop_details <- trip_stops_info[route_key];
                        bool first_detail <- true;
                        
                        loop detail over: stop_details {
                            if !first_detail {
                                json_content <- json_content + ", ";
                            }
                            first_detail <- false;
                            json_content <- json_content + "\"" + detail + "\"";
                        }
                        
                        json_content <- json_content + "]";
                    }
                    
                    json_content <- json_content + "\n        }";
                }
                
                json_content <- json_content + "\n      }\n    }";
            }
            
            json_content <- json_content + "\n  ]\n}";
            
            save json_content to: json_path format: "text";
            write "✅ DEPARTUREINFO JSON STRUCTURE COMPLÈTE EXPORTÉE : " + json_path;
            write "📊 " + stops_exported + " arrêts avec departureStopsInfo exportés";
            write "📋 Structure : map<string, map<string, list<string>>> préservée";
            
        } catch {
            write "❌ Erreur export departureInfo JSON structure complète";
        }
    }
    
    // 📋 EXPORT RÉSUMÉ STATISTIQUES 
    action export_summary_simple {
        write "\n📋 === EXPORT RÉSUMÉ MATCHING ===";
        
        string summary_path <- export_folder + "stops_matching_summary.txt";
        
        try {
            string summary_content <- "=== RÉSUMÉ MATCHING STOPS GTFS + DEPARTUREINFO ===\n";
            summary_content <- summary_content + "Date export: " + current_date + "\n\n";
            
            summary_content <- summary_content + "DONNÉES SOURCES:\n";
            summary_content <- summary_content + "- Routes bus (shapefile): " + total_bus_routes + "\n";
            summary_content <- summary_content + "- Arrêts GTFS: " + nb_total_stops + "\n\n";
            
            summary_content <- summary_content + "RÉSULTATS MATCHING:\n";
            summary_content <- summary_content + "- Arrêts matchés: " + nb_stops_matched + "/" + nb_total_stops;
            
            if nb_total_stops > 0 {
                float match_rate <- (nb_stops_matched / nb_total_stops) * 100;
                summary_content <- summary_content + " (" + int(match_rate) + "%)\n";
            } else {
                summary_content <- summary_content + "\n";
            }
            
            summary_content <- summary_content + "- Trips mappés: " + length(tripId_to_osm_id_majoritaire) + "\n\n";
            
            // Statistiques qualité
            if nb_stops_matched > 0 {
                list<bus_stop> matched_stops <- bus_stop where (each.is_matched);
                int excellent <- length(matched_stops where (each.closest_route_dist <= 300));
                int good <- length(matched_stops where (each.closest_route_dist > 300 and each.closest_route_dist <= 600));
                int poor <- length(matched_stops where (each.closest_route_dist > 600));
                
                summary_content <- summary_content + "QUALITÉ MATCHING:\n";
                summary_content <- summary_content + "- Excellent (≤300m): " + excellent + " (" + int((excellent/nb_stops_matched)*100) + "%)\n";
                summary_content <- summary_content + "- Bon (300-600m): " + good + " (" + int((good/nb_stops_matched)*100) + "%)\n";
                summary_content <- summary_content + "- Moyen (>600m): " + poor + " (" + int((poor/nb_stops_matched)*100) + "%)\n\n";
            }
            
            // 🆕 Statistiques departureInfo
            int stops_with_departure <- length(bus_stop where (each.departure_info_json != nil and each.departure_info_json != ""));
            summary_content <- summary_content + "DEPARTUREINFO:\n";
            summary_content <- summary_content + "- Arrêts avec departureInfo: " + stops_with_departure + "/" + nb_total_stops;
            summary_content <- summary_content + " (" + int((stops_with_departure/nb_total_stops)*100) + "%)\n\n";
            
            summary_content <- summary_content + "FICHIERS EXPORTÉS:\n";
            summary_content <- summary_content + "- gtfs_stops_complete.shp : Arrêts avec matching + departureInfo\n";
            summary_content <- summary_content + "- trip_to_route_mapping.csv : Correspondances trips\n";
            summary_content <- summary_content + "- departure_stops_info_complete.json : DepartureInfo structure complète\n";
            summary_content <- summary_content + "- stops_matching_summary.txt : Ce résumé\n\n";
            
            summary_content <- summary_content + "UTILISATION:\n";
            summary_content <- summary_content + "1. Charger gtfs_stops_complete.shp dans votre SIG\n";
            summary_content <- summary_content + "2. Utiliser 'closest_id' pour lier avec routes existantes\n";
            summary_content <- summary_content + "3. Utiliser 'departure_json' pour info trips détaillées\n";
            summary_content <- summary_content + "4. Utiliser CSV pour mapping trips → routes OSM\n";
            summary_content <- summary_content + "5. Utiliser JSON pour analyses complètes departureInfo\n";
            summary_content <- summary_content + "6. JSON préserve la structure map<string, map<string, list<string>>>\n";
            
            save summary_content to: summary_path format: "text";
            write "✅ RÉSUMÉ EXPORTÉ : " + summary_path;
            
        } catch {
            write "❌ Erreur export résumé";
        }
    }
    
    // 🎯 ACTION PRINCIPALE D'EXPORT STOPS + DEPARTUREINFO
    action export_all_matching_results {
        write "\n🎯 === EXPORT STOPS GTFS + DEPARTUREINFO + MAPPING ===";
        
        // 1. Export arrêts GTFS complets + departureInfo
        do export_gtfs_stops_complete;
        
        // 2. Export mapping trips
        do export_trip_mapping_simple;
        
        // 3. Export departureInfo JSON avec structure complète préservée
        do export_departure_info_complete;
        
        // 4. Export résumé
        do export_summary_simple;
        
        write "\n✅ === EXPORT COMPLET TERMINÉ ===";
        write "📁 Dossier: " + export_folder;
        write "📊 Fichiers créés:";
        write "  - gtfs_stops_complete.shp (arrêts + tous attributs + matching + departureInfo)";
        write "  - trip_to_route_mapping.csv (correspondances trip → route)";
        write "  - departure_stops_info_complete.json (departureInfo structure complète préservée)";
        write "  - stops_matching_summary.txt (résumé qualité)";
        write "💡 Utilisez 'closest_id' pour lier avec vos routes existantes";
        write "💡 Utilisez 'departure_json' dans le shapefile pour info trips de base";
        write "💡 JSON préserve map<string, map<string, list<string>>> pour rechargement exact";
    }
}

// 🚌 AGENT ROUTE BUS
species bus_route {
    string route_name;
    string osm_id;
    string route_type;
    string highway_type;
    float length_meters;
    int zone_id;  // ✅ Zone spatiale
    
    aspect default {
        if shape != nil {
            draw shape color: #blue width: 2.0;
        }
    }
    
    aspect thick {
        if shape != nil {
            draw shape color: #blue width: 3.0;
        }
    }
    
    aspect labeled {
        if shape != nil {
            draw shape color: #blue width: 3.0;
            if route_name != nil and route_name != "" and route_name != "name" {
                draw route_name size: 12 color: #black at: location + {0, 10};
            }
        }
    }
}

// 🚏 AGENT ARRÊT BUS GTFS + DEPARTUREINFO SÉRIALISÉ
species bus_stop skills: [TransportStopSkill] {
    // Attributs de matching
    string closest_route_id <- "";
    int closest_route_index <- -1;
    float closest_route_dist <- -1.0;
    bool is_matched <- false;
    int zone_id;  // ✅ Zone spatiale
    
    // ✅ ATTRIBUTS ENRICHIS POUR EXPORT
    string is_matched_str <- "FALSE";
    string match_quality <- "NONE";
    
    // 🆕 ATTRIBUTS DEPARTUREINFO SÉRIALISÉS POUR EXPORT SHAPEFILE
    string departure_info_json <- "";      // JSON complet (limité par taille shapefile)
    string departure_info_tripids <- "";   // Liste trip_ids séparés par virgules
    int departure_info_count <- 0;         // Nombre de trips
    
    // Données GTFS (attribut complexe original)
    map<string, map<string, list<string>>> departureStopsInfo;
    
    // 🆕 ACTION DE SÉRIALISATION DEPARTUREINFO
    action serialize_departure_info {
        if departureStopsInfo = nil or empty(departureStopsInfo) {
            departure_info_json <- "";
            departure_info_tripids <- "";
            departure_info_count <- 0;
            return;
        }
        
        try {
            // Méthode 1: Créer JSON simplifié (limité par taille)
            string json_str <- "{";
            bool first_trip <- true;
            list<string> trip_ids_list <- [];
            
            loop trip_id over: departureStopsInfo.keys {
                trip_ids_list <+ trip_id;
                
                if !first_trip {
                    json_str <- json_str + ",";
                }
                first_trip <- false;
                
                // JSON simplifié: juste trip_id et nombre de stops
                map<string, list<string>> trip_info <- departureStopsInfo[trip_id];
                int stops_in_trip <- 0;
                
                loop route_info over: trip_info.values {
                    stops_in_trip <- stops_in_trip + length(route_info);
                }
                
                json_str <- json_str + "\"" + trip_id + "\":" + stops_in_trip;
                
                // Limiter taille JSON (shapefiles ont limite ~254 caractères par champ)
                if length(json_str) > 200 {
                    json_str <- json_str + "...";
                    break;
                }
            }
            
            json_str <- json_str + "}";
            departure_info_json <- json_str;
            
            // Méthode 2: Liste trip_ids (plus robuste)
            departure_info_tripids <- "";
            loop i from: 0 to: (length(trip_ids_list) - 1) {
                if i > 0 {
                    departure_info_tripids <- departure_info_tripids + ",";
                }
                departure_info_tripids <- departure_info_tripids + trip_ids_list[i];
                
                // Limiter taille pour shapefile
                if length(departure_info_tripids) > 200 {
                    departure_info_tripids <- departure_info_tripids + "...";
                    break;
                }
            }
            
            // Méthode 3: Compteur (toujours fiable)
            departure_info_count <- length(trip_ids_list);
            
        } catch {
            // Fallback en cas d'erreur
            departure_info_json <- "ERROR_SERIALIZATION";
            departure_info_tripids <- "ERROR";
            departure_info_count <- -1;
        }
    }
    
    aspect default {
        draw circle(150.0) color: is_matched ? #green : #red;
    }
    
    aspect detailed {
        draw circle(150.0) color: is_matched ? #green : #red;
        if is_matched {
            draw "✅" size: 15 color: #white at: location;
        } else {
            draw "❌" size: 15 color: #white at: location;
        }
    }
    
    aspect with_distance {
        rgb stop_color;
        if !is_matched {
            stop_color <- #red;
        } else if closest_route_dist <= 300 {
            stop_color <- #green;
        } else if closest_route_dist <= 600 {
            stop_color <- #orange;
        } else {
            stop_color <- #yellow;
        }
        
        draw circle(150.0) color: stop_color;
        
        if is_matched and closest_route_dist >= 0 {
            draw string(int(closest_route_dist)) + "m" 
                 size: 10 color: #black at: location + {0, 200};
        }
    }
    
    // 🆕 ASPECT AVEC INFO TRIPS
    aspect with_trip_info {
        rgb stop_color;
        if !is_matched {
            stop_color <- #red;
        } else if closest_route_dist <= 300 {
            stop_color <- #green;
        } else if closest_route_dist <= 600 {
            stop_color <- #orange;
        } else {
            stop_color <- #yellow;
        }
        
        draw circle(150.0) color: stop_color;
        
        // Afficher nombre de trips
        if departure_info_count > 0 {
            draw string(departure_info_count) + " trips" 
                 size: 8 color: #black at: location + {0, -200};
        }
        
        if is_matched and closest_route_dist >= 0 {
            draw string(int(closest_route_dist)) + "m" 
                 size: 10 color: #black at: location + {0, 200};
        }
    }
}

// 🎯 EXPÉRIMENT PRINCIPAL AVEC MATCHING + DEPARTUREINFO
experiment bus_network_with_gtfs_matching type: gui {
    
    // Paramètres ajustables
    parameter "Taille grille (m)" var: grid_size min: 200 max: 1000 step: 100;
    parameter "Rayon max recherche (m)" var: max_global_search_radius min: 1000 max: 5000 step: 500;
    parameter "Taille batch" var: batch_size min: 50 max: 500 step: 50;
    
    // Actions menu
    action reload_all {
        ask world {
            do reload_network_and_matching;
        }
    }
    
    action fit_to_data {
        ask world {
            do create_envelope_from_data;
        }
    }
    
    user_command "Recharger tout" action: reload_all;
    user_command "Fit to Data" action: fit_to_data;
    
    output {
        display "Réseau Bus + Arrêts GTFS + DepartureInfo" background: #white type: 2d {
            // Routes de bus en bleu
            species bus_route aspect: thick;
            // Arrêts GTFS avec état matching
            species bus_stop aspect: with_trip_info;
            
            overlay position: {10, 10} size: {350 #px, 190 #px} background: #white transparency: 0.9 border: #black {
                draw "=== RÉSEAU BUS HANOI + DEPARTUREINFO ===" at: {10#px, 20#px} color: #black font: font("Arial", 11, #bold);
                
                // Statistiques essentielles
                draw "🚌 Routes : " + length(bus_route) at: {20#px, 45#px} color: #blue font: font("Arial", 10, #bold);
                draw "🚏 Arrêts : " + length(bus_stop) at: {20#px, 65#px} color: #black font: font("Arial", 10, #bold);
                
                // Résultat matching
                if length(bus_stop) > 0 {
                    int matched <- length(bus_stop where (each.is_matched));
                    float match_rate <- (matched / length(bus_stop)) * 100;
                    
                    draw "✅ Matchés : " + matched + " (" + int(match_rate) + "%)" at: {20#px, 90#px} color: #green;
                    draw "🗺️ Trips mappés : " + length(tripId_to_osm_id_majoritaire) at: {20#px, 110#px} color: #blue;
                    
                    // 🆕 Info departureInfo
                    int stops_with_departure <- length(bus_stop where (each.departure_info_count > 0));
                    draw "📋 Avec departureInfo : " + stops_with_departure + " (" + int((stops_with_departure/length(bus_stop))*100) + "%)" at: {20#px, 130#px} color: #purple;
                }
            }
        }
    }
}