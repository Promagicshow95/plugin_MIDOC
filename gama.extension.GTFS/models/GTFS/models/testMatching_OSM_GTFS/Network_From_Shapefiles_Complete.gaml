/**
 * Name: Network_From_Shapefiles_Complete_Optimized
 * Author: Promagicshow95
 * Description: Reconstruction réseau bus + stops avec departureStopsInfo OPTIMISÉ
 * Tags: shapefile, network, bus, stops, gtfs, reconstruction, optimized
 * Date: 2025-08-26
 * 
 * OPTIMISATION DEPARTUREINFO:
 * - Parse JSON unique au lieu de N fois
 * - Structures globales pour accès O(1)
 * - Conversion automatique stopId -> agents
 * - Compatible simulation véhicules avec horaires
 */

model Network_From_Shapefiles_Complete_Optimized

global {
    // --- CONFIGURATION FICHIERS ---
    string results_folder <- "../../results/";
    string stops_folder <- "../../results/stopReseau/";
    string export_folder <- "../../results/export/";
    
    file data_file <- shape_file("../../includes/shapeFileHanoishp.shp");
    geometry shape <- envelope(data_file);
    
    // --- VARIABLES STATISTIQUES ---
    int total_bus_routes <- 0;
    int total_bus_stops <- 0;
    int total_network_elements <- 0;
    
    // --- PARAMÈTRES D'AFFICHAGE ---
    bool show_routes <- true;
    bool show_stops <- true;
    
    // 🚀 STRUCTURES OPTIMISÉES DEPARTUREINFO
    // Étape 1: Structure temporaire pour parsing JSON
    map<string, map<string, list<pair<string, int>>>> stop_to_all_trips;
    // stopId -> tripId -> [(stopId, heure), (stopId, heure)...]
    
    // Étape 2: Map de conversion
    map<string, bus_stop> stopId_to_agent;
    // "01_1_S1" -> agent_bus_stop_123
    
    // Étape 3: Structure finale optimisée
    map<string, list<pair<bus_stop, int>>> trip_to_agents_with_times;
    // "01_1_MD_1" -> [(agent_S1, 34200), (agent_S2, 34467)...]
    
    // Statistiques optimisation
    int json_parse_time <- 0;
    int total_trips_found <- 0;
    int successful_conversions <- 0;

    init {
        write "=== RÉSEAU BUS AVEC DEPARTUREINFO OPTIMISÉ ===";
        
        // ÉTAPE 1: CHARGEMENT STANDARD
        if show_routes {
            do load_bus_network_robust;
        }
        if show_stops {
            do load_gtfs_stops_from_shapefile;
        }
        
        // ÉTAPE 2: OPTIMISATION DEPARTUREINFO
        do build_optimized_departure_structures;
        
        // ÉTAPE 3: VALIDATION ET STATS
        do validate_world_envelope;
        do display_optimized_statistics;
        do validate_loaded_data;
    }
    
    // 🚌 CHARGEMENT RÉSEAU BUS (INCHANGÉ)
    action load_bus_network_robust {
        write "\n🚌 === CHARGEMENT RÉSEAU BUS ===";
        
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
                write "  ℹ️ Fin détection à part" + i;
                continue_loading <- false;
            }
        }
        
        total_bus_routes <- bus_routes_count;
        write "📊 TOTAL BUS : " + bus_routes_count + " routes";
    }
    
    // 🚏 CHARGEMENT ARRÊTS (INCHANGÉ)
    action load_gtfs_stops_from_shapefile {
        write "\n🚏 === CHARGEMENT STOPS ===";
        
        string stops_filename <- stops_folder + "gtfs_stops_complete.shp";
        
        try {
            file shape_file_stops <- shape_file(stops_filename);
            
            create bus_stop from: shape_file_stops with: [
                stopId::string(read("stopId")),
                stop_name::string(read("name")),
                stopName::string(read("stopName")),
                routeType::int(read("routeType")),
                tripNumber::int(read("tripNumber")),
                closest_route_id::string(read("closest_id")),
                closest_route_index::int(read("closest_idx")),
                closest_route_dist::float(read("distance")),
                is_matched_str::string(read("matched")),
                match_quality::string(read("quality")),
                zone_id::int(read("zone_id"))
            ];
            
            total_bus_stops <- length(shape_file_stops);
            
            ask bus_stop {
                is_matched <- (is_matched_str = "TRUE");
                if stopId = nil or stopId = "" {
                    stopId <- "stop_" + string(int(self));
                }
                if stop_name = nil or stop_name = "" {
                    stop_name <- "Stop_" + string(int(self));
                }
            }
            
            write "✅ " + total_bus_stops + " arrêts chargés";
            
        } catch {
            write "❌ Erreur chargement stops";
            total_bus_stops <- 0;
        }
    }
    
    // 🚀 CONSTRUCTION STRUCTURES OPTIMISÉES
    action build_optimized_departure_structures {
        write "\n🚀 === CONSTRUCTION STRUCTURES OPTIMISÉES ===";
        
        // ÉTAPE 1: Parse unique JSON
        do parse_json_to_temporary_structure;
        
        // ÉTAPE 2: Construire map conversion
        do build_stopId_to_agent_map;
        
        // ÉTAPE 3: Convertir vers structure finale
        do convert_to_final_structure;
        
        write "✅ Structures optimisées construites";
    }
    
    // ÉTAPE 1: PARSE UNIQUE JSON
    action parse_json_to_temporary_structure {
        write "📄 Parse unique JSON...";
        
        string json_filename <- stops_folder + "departure_stops_info_complete.json";
        int start_time <- cycle;
        
        try {
            file departure_json_file <- text_file(json_filename);
            string json_content <- "";
            loop line over: departure_json_file.contents {
                json_content <- json_content + line + "\n";
            }
            
            // Initialiser structure temporaire
            stop_to_all_trips <- map<string, map<string, list<pair<string, int>>>>([]);
            
            // Parser avec méthode robuste
            do parse_json_content_optimized(json_content);
            
            json_parse_time <- cycle - start_time;
            write "✅ Parse JSON terminé en " + json_parse_time + " cycles";
            
        } catch {
            write "❌ Erreur lecture JSON : " + json_filename;
            stop_to_all_trips <- map<string, map<string, list<pair<string, int>>>>([]);
        }
    }
    
    // PARSER CONTENU JSON OPTIMISÉ
    action parse_json_content_optimized(string json_content) {
        list<string> lines <- json_content split_with "\n";
        
        string current_stop_id <- "";
        string current_trip_id <- "";
        bool in_departure_block <- false;
        int brace_count <- 0;
        
        loop line over: lines {
            string clean_line <- line replace ("  ", "") replace ("\t", "") replace ("\"", "");
            
            // Détecter stopId
            if (clean_line contains "stopId:") {
                list<string> parts <- clean_line split_with ":";
                if length(parts) >= 2 {
                    current_stop_id <- parts[1] replace (",", "") replace (" ", "");
                    if !(stop_to_all_trips contains_key current_stop_id) {
                        stop_to_all_trips[current_stop_id] <- map<string, list<pair<string, int>>>([]);
                    }
                }
            }
            
            // Détecter début departureStopsInfo
            if (clean_line contains "departureStopsInfo:") {
                in_departure_block <- true;
                brace_count <- 0;
            }
            
            if in_departure_block {
                // Compter accolades
                loop i from: 0 to: (length(line) - 1) {
                    string char <- copy(line) at i;
                    if char = "{" { brace_count <- brace_count + 1; }
                    else if char = "}" { brace_count <- brace_count - 1; }
                }
                
                // Détecter tripId et parser son contenu
                if (clean_line contains ":") and 
                   !(clean_line contains "departureStopsInfo") and 
                   !(clean_line contains "stopId") and 
                   !(clean_line contains "name") and
                   !(clean_line contains "location") {
                    
                    list<string> parts <- clean_line split_with ":";
                    if length(parts) >= 2 {
                        current_trip_id <- parts[0] replace (",", "") replace (" ", "");
                        
                        if current_trip_id != "" and current_stop_id != "" {
                            // Parser itinéraire complet du trip
                            string schedule_part <- parts[1];
                            list<pair<string, int>> trip_schedule <- [];
                            
                            do parse_trip_schedule_complete(schedule_part, trip_schedule);
                            
                            // Stocker dans structure temporaire
                            if !empty(trip_schedule) {
                                stop_to_all_trips[current_stop_id][current_trip_id] <- trip_schedule;
                                total_trips_found <- total_trips_found + 1;
                            }
                        }
                    }
                }
                
                // Fin du bloc
                if brace_count <= 0 {
                    in_departure_block <- false;
                    current_stop_id <- "";
                    current_trip_id <- "";
                }
            }
        }
        
        write "📊 Trips trouvés : " + total_trips_found;
    }
    
    // PARSER HORAIRE COMPLET D'UN TRIP
    action parse_trip_schedule_complete(string schedule_text, list<pair<string, int>> result) {
        try {
            // Enlever les crochets et parser par paires
            schedule_text <- schedule_text replace ("[", "") replace ("]", "");
            list<string> elements <- schedule_text split_with ",";
            
            if length(elements) >= 2 and (length(elements) mod 2 = 0) {
                loop i from: 0 to: (length(elements) - 1) step: 2 {
                    string stop_id <- elements[i] replace (" ", "") replace ("\"", "");
                    string time_str <- elements[i + 1] replace (" ", "") replace ("\"", "");
                    
                    if stop_id != "" and time_str != "" {
                        int time_seconds <- 0;
                        try {
                            time_seconds <- int(time_str);
                        } catch {
                            time_seconds <- 0;
                        }
                        
                        if time_seconds > 0 {
                            result <+ pair(stop_id, time_seconds);
                        }
                    }
                }
            }
            
        } catch {
            write "⚠️ Erreur parsing horaire trip";
        }
    }
    
    // ÉTAPE 2: CONSTRUIRE MAP CONVERSION
    action build_stopId_to_agent_map {
        write "🔗 Construction map stopId -> agent...";
        
        stopId_to_agent <- map<string, bus_stop>([]);
        
        ask bus_stop {
            if stopId != nil and stopId != "" {
                stopId_to_agent[stopId] <- self;
            }
        }
        
        write "✅ " + length(stopId_to_agent) + " conversions créées";
    }
    
    // ÉTAPE 3: CONVERTIR VERS STRUCTURE FINALE
    action convert_to_final_structure {
        write "🏗️ Conversion vers structure finale...";
        
        trip_to_agents_with_times <- map<string, list<pair<bus_stop, int>>>([]);
        successful_conversions <- 0;
        
        // Pour chaque stop dans structure temporaire
        loop stop_id over: stop_to_all_trips.keys {
            map<string, list<pair<string, int>>> trips_from_stop <- stop_to_all_trips[stop_id];
            
            // Pour chaque trip depuis ce stop
            loop trip_id over: trips_from_stop.keys {
                if !(trip_to_agents_with_times contains_key trip_id) {
                    list<pair<string, int>> schedule <- trips_from_stop[trip_id];
                    list<pair<bus_stop, int>> agents_with_times <- [];
                    
                    // Convertir stopId -> agents
                    bool conversion_success <- true;
                    loop stop_time_pair over: schedule {
                        string stop_id_in_trip <- stop_time_pair.key;
                        int time <- stop_time_pair.value;
                        
                        if stopId_to_agent contains_key stop_id_in_trip {
                            bus_stop stop_agent <- stopId_to_agent[stop_id_in_trip];
                            agents_with_times <+ pair(stop_agent, time);
                        } else {
                            conversion_success <- false;
                            break;
                        }
                    }
                    
                    // Stocker si succès
                    if conversion_success and !empty(agents_with_times) {
                        trip_to_agents_with_times[trip_id] <- agents_with_times;
                        successful_conversions <- successful_conversions + 1;
                    }
                }
            }
        }
        
        write "✅ " + successful_conversions + " trips convertis avec agents + horaires";
    }
    
    // 🚀 APIs D'ACCÈS OPTIMISÉES
    
    // Obtenir itinéraire complet d'un trip (agents + heures)
    list get_trip_route(string trip_id) {
        if trip_to_agents_with_times contains_key trip_id {
            return trip_to_agents_with_times[trip_id];
        }
        return [];
    }
    
    // Obtenir agent correspondant à un stopId
    bus_stop get_stop_agent(string stop_id) {
        if stopId_to_agent contains_key stop_id {
            return stopId_to_agent[stop_id];
        }
        return nil;
    }
    
    // Obtenir tous les trips disponibles
    list get_all_trip_ids {
        return trip_to_agents_with_times.keys;
    }
    
    // Obtenir trips depuis un arrêt
    list get_trips_from_stop(string stop_id) {
        if stop_to_all_trips contains_key stop_id {
            return stop_to_all_trips[stop_id].keys;
        }
        return [];
    }
   
    
    // 📊 STATISTIQUES OPTIMISÉES
    action display_optimized_statistics {
        write "\n📊 === STATISTIQUES OPTIMISÉES ===";
        write "🚌 Routes Bus : " + total_bus_routes;
        write "🚏 Arrêts GTFS : " + total_bus_stops;
        write "⏱️ Temps parse JSON : " + json_parse_time + "ms";
        write "🔄 Trips trouvés : " + total_trips_found;
        write "✅ Conversions réussies : " + successful_conversions;
        write "🗂️ Structures en mémoire :";
        write "  - stop_to_all_trips : " + length(stop_to_all_trips);
        write "  - stopId_to_agent : " + length(stopId_to_agent);
        write "  - trip_to_agents_with_times : " + length(trip_to_agents_with_times);
        
        // Exemple d'utilisation
        if !empty(trip_to_agents_with_times) {
            string sample_trip <- first(trip_to_agents_with_times.keys);
            list<pair<bus_stop, int>> sample_route <- trip_to_agents_with_times[sample_trip];
            
            write "\n💡 Exemple d'utilisation :";
            write "  Trip : " + sample_trip;
            write "  Arrêts dans ce trip : " + length(sample_route);
            if !empty(sample_route) {
                pair<bus_stop, int> first_stop <- first(sample_route);
                write "  Premier arrêt : " + first_stop.key.stopId + " à " + first_stop.value + "s";
            }
        }
    }
    
    // ACTIONS HÉRITÉES (simplifiées)
    action validate_world_envelope {
        write "\n🌍 === VALIDATION ENVELOPPE ===";
        if shape != nil {
            write "✅ Enveloppe définie : " + shape.width + " x " + shape.height;
        } else {
            write "❌ Enveloppe non définie";
        }
    }
    
    action validate_loaded_data {
        write "\n🔍 === VALIDATION DONNÉES ===";
        
        if length(bus_route) > 0 {
            bus_route sample_route <- first(bus_route);
            write "✅ Échantillon Route : " + (sample_route.route_name != nil ? sample_route.route_name : "VIDE");
        }
        
        if length(bus_stop) > 0 {
            bus_stop sample_stop <- first(bus_stop);
            write "✅ Échantillon Arrêt : " + (sample_stop.stopId != nil ? sample_stop.stopId : "VIDE");
        }
        
        write "🎯 VALIDATION TERMINÉE";
    }
    
    // ACTION RECHARGEMENT
    action reload_optimized_network {
        write "\n🔧 === RECHARGEMENT OPTIMISÉ ===";
        
        ask bus_route { do die; }
        ask bus_stop { do die; }
        ask vehicle { do die; }
        
        total_bus_routes <- 0;
        total_bus_stops <- 0;
        
        if show_routes { do load_bus_network_robust; }
        if show_stops { do load_gtfs_stops_from_shapefile; }
        
        do build_optimized_departure_structures;
        do display_optimized_statistics;
        
        write "🔄 Rechargement optimisé terminé";
    }
}

// 🚌 AGENT ROUTE BUS (INCHANGÉ)
species bus_route {
    string route_name;
    string osm_id;
    string route_type;
    string highway_type;
    float length_meters;
    int zone_id;
    
    aspect default {
        if shape != nil {
            draw shape color: #blue width: 1.5;
        }
    }
}

// 🚏 AGENT ARRÊT BUS SIMPLIFIÉ (PLUS DE DEPARTUREINFO STOCKÉ)
species bus_stop {
    string stopId <- "";
    string stop_name <- "";
    string stopName <- "";
    int routeType <- 0;
    int tripNumber <- 0;
    
    // Attributs de matching
    string closest_route_id <- "";
    int closest_route_index <- -1;
    float closest_route_dist <- -1.0;
    bool is_matched <- false;
    string is_matched_str <- "FALSE";
    string match_quality <- "NONE";
    int zone_id;
    
    // PLUS DE departureStopsInfo - tout dans structures globales
    
    aspect default {
        draw circle(100.0) color: #red;
        
        // Indicateur si ce stop a des trips
        list trips <- world.get_trips_from_stop(stopId);
        if !empty(trips) {
            draw circle(150.0) border: #blue width: 2;
            draw string(length(trips)) at: location + {0, 200} color: #blue size: 12;
        }
    }
}

// 🚗 AGENT VÉHICULE UTILISANT STRUCTURES OPTIMISÉES
species vehicle skills: [moving] {
    string trip_id;
    list planned_route;  // AGENTS + HEURES
    int current_stop_index <- 0;
    int start_time;
    bool is_moving <- false;
    
    reflex move_when_scheduled when: !is_moving and current_stop_index < length(planned_route) {
        pair<bus_stop, int> next_stop_info <- planned_route[current_stop_index];
        bus_stop target_agent <- next_stop_info.key;
        int scheduled_time <- next_stop_info.value;
        
        // Vérifier horaire (adaptez selon votre échelle temps)
        int current_simulation_time <- cycle * 1;
        
        if current_simulation_time >= scheduled_time {
            do goto target: target_agent.location speed: 50.0;
            is_moving <- true;
        }
    }
    

}

// 🎯 EXPÉRIMENT AVEC VÉHICULES
experiment network_optimized type: gui {
    
    action reload_all {
        ask world { do reload_optimized_network; }
    }
    

    
    action show_stats {
        ask world { do display_optimized_statistics; }
    }
    
    user_command "Recharger Optimisé" action: reload_all;
    user_command "Afficher Stats" action: show_stats;
    
    output {
        display "Réseau Bus Optimisé" background: #white type: 2d {
            species bus_route aspect: default;
            species bus_stop aspect: default;
           
            
            overlay position: {10, 10} size: {350 #px, 160 #px} background: #white transparency: 0.9 border: #black {
                draw "=== RÉSEAU BUS OPTIMISÉ ===" at: {10#px, 20#px} color: #black font: font("Arial", 12, #bold);
                
                draw "🚌 Routes : " + length(bus_route) at: {20#px, 45#px} color: #blue;
                draw "🚏 Arrêts : " + length(bus_stop) at: {20#px, 65#px} color: #red;
                draw "🚗 Véhicules : " + length(vehicle) at: {20#px, 85#px} color: #green;
                
                // Stats optimisation
                if world.successful_conversions > 0 {
                    draw "✅ Trips convertis : " + world.successful_conversions at: {20#px, 105#px} color: #green;
                    draw "⏱️ Parse JSON : " + world.json_parse_time + "ms" at: {20#px, 125#px} color: #purple;
                }
                
                draw "🔵 Routes  🔴 Arrêts  🟢 Véhicules" at: {20#px, 145#px} color: #black size: 9;
            }
        }
    }
}