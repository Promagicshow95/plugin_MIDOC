/**
 * Name: ModeleReseauBusAvecJSON
 * Author: Combined - Network + JSON Processing
 * Description: Chargement réseau bus + traitement JSON trip_to_sequence
 */

model ModeleReseauBusAvecJSON

global {
    // CONFIGURATION FICHIERS
    string results_folder <- "../../results/";
    string stops_folder <- "../../results/stopReseau/";
    
    file data_file <- shape_file("../../includes/shapeFileHanoishp.shp");
    geometry shape <- envelope(data_file);
    
    // VARIABLES RÉSEAU (du modèle visualisation)
    int total_bus_routes <- 0;
    int total_bus_stops <- 0;
    int matched_stops <- 0;
    int unmatched_stops <- 0;
    bool debug_mode <- false; // Réduit la verbosité
    
    // STRUCTURES RÉSEAU
    map<string, bus_stop> stopId_to_agent;
    map<string, bus_route> osmId_to_route;
    
    // VARIABLES JSON (du modèle traitement)
    map<string, list<pair<string, int>>> trip_to_sequence;
    int total_stops_processed <- 0;
    int total_trips_processed <- 0;
    map<string, int> collision_check;
    
    // NOUVELLE STRUCTURE : TRIP -> ROUTE OSM DOMINANTE
    map<string, string> trip_to_route; // trip_id -> osm_id dominant
    
    // ROUTE MISE EN ÉVIDENCE POUR TRIP 01_1_MD_14
    string highlighted_route_osm_id <- "";
    bus_route highlighted_route_agent <- nil;

    init {
        write "=== MODÈLE COMBINÉ RÉSEAU + JSON ===";
        
        // 1. CHARGEMENT RÉSEAU (shapefiles)
        do load_bus_network;
        do load_gtfs_stops;
        do build_basic_mappings;
        
        // 2. TRAITEMENT JSON (trip_to_sequence)
        do process_json_trips;
        
        // 3. CALCUL ROUTES DOMINANTES POUR TRIPS
        do compute_trip_to_route_mappings;
        
        // 4. IDENTIFIER ROUTE POUR TRIP 01_1_MD_14
        do highlight_trip_route;
        
        // 5. VÉRIFICATIONS DES STRUCTURES
        do verify_data_structures;
        
        write "\n🎯 INITIALISATION TERMINÉE";
        write "  • Routes: " + total_bus_routes;
        write "  • Arrêts: " + total_bus_stops + " (matchés: " + matched_stops + ")";
        write "  • Trips: " + length(trip_to_sequence.keys);
        write "  • Trips avec routes: " + length(trip_to_route.keys);
    }
    
    // IDENTIFIER ET METTRE EN ÉVIDENCE LA ROUTE D'UN TRIP DISPONIBLE
    action highlight_trip_route {
        string target_trip_id <- "";
        
        // CHERCHER D'ABORD "01_1_MD_14", sinon prendre le premier trip disponible
        if trip_to_route contains_key "01_1_MD_14" {
            target_trip_id <- "01_1_MD_14";
        } else if length(trip_to_route.keys) > 0 {
            target_trip_id <- first(trip_to_route.keys);
            write "⚠️ Trip '01_1_MD_14' non trouvé, utilisation du trip: " + target_trip_id;
        } else {
            write "❌ Aucun trip avec route trouvé dans les données";
            return;
        }
        
        write "\n🔍 RECHERCHE ROUTE POUR TRIP: " + target_trip_id;
        
        // Vérifier si le trip existe dans trip_to_route
        if trip_to_route contains_key target_trip_id {
            highlighted_route_osm_id <- trip_to_route[target_trip_id];
            write "✅ Route OSM ID trouvée: " + highlighted_route_osm_id;
            
            // Utiliser osmId_to_route pour trouver l'agent route
            highlighted_route_agent <- get_route_by_osm_id(highlighted_route_osm_id);
            
            if highlighted_route_agent != nil {
                write "✅ Agent route trouvé:";
                write "   • Nom: " + highlighted_route_agent.route_name;
                write "   • Type: " + highlighted_route_agent.route_type;
                write "   • Longueur: " + round(highlighted_route_agent.length_meters) + "m";
                write "   • Cette route sera affichée en ROUGE";
            } else {
                write "❌ Agent route non trouvé pour OSM ID: " + highlighted_route_osm_id;
                highlighted_route_osm_id <- "";
            }
        } else {
            write "❌ Trip " + target_trip_id + " non trouvé dans trip_to_route";
            
            // Afficher quelques trips disponibles comme suggestion
            write "💡 Trips disponibles (premiers 5):";
            int count <- 0;
            loop trip_id over: trip_to_route.keys {
                if count < 5 {
                    write "   • " + trip_id;
                    count <- count + 1;
                }
            }
        }
        
        write "=====================================";
    }

    // ==================== SECTION RÉSEAU ====================
    
    // CHARGEMENT RÉSEAU BUS
    action load_bus_network {
        write "\n1. CHARGEMENT RÉSEAU BUS";
        
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
                
                bus_routes_count <- bus_routes_count + length(shape_file_bus);
                i <- i + 1;
                
                if debug_mode {
                    write "Fichier " + i + " : " + length(shape_file_bus) + " routes";
                }
                
            } catch {
                if i = 0 {
                    write "⚠️ Aucun fichier de routes trouvé";
                }
                continue_loading <- false;
            }
        }
        
        total_bus_routes <- bus_routes_count;
        write "Routes chargées : " + bus_routes_count;
        
        // Nettoyer les routes sans géométrie
        ask bus_route where (each.shape = nil) {
            do die;
        }
        
        total_bus_routes <- length(bus_route);
        write "Routes avec géométrie valide : " + total_bus_routes;
    }
    
    // CHARGEMENT ARRÊTS GTFS
    action load_gtfs_stops {
        write "\n2. CHARGEMENT ARRÊTS GTFS";
        
        string stops_filename <- stops_folder + "gtfs_stops_complete.shp";
        
        try {
            file shape_file_stops <- shape_file(stops_filename);
            
            create bus_stop from: shape_file_stops with: [
                stopId::string(read("stopId")),
                stop_name::string(read("name")),
                closest_route_id::string(read("closest_id")),
                closest_route_dist::float(read("distance")),
                is_matched_str::string(read("matched"))
            ];
            
            total_bus_stops <- length(shape_file_stops);
            
            // Nettoyer et valider les arrêts
            ask bus_stop {
                is_matched <- (is_matched_str = "TRUE");
                
                if stopId = nil or stopId = "" {
                    stopId <- "stop_" + string(int(self));
                }
                if stop_name = nil or stop_name = "" {
                    stop_name <- "Stop_" + string(int(self));
                }
                
                // Compter les arrêts matchés/non-matchés
                if is_matched {
                    matched_stops <- matched_stops + 1;
                } else {
                    unmatched_stops <- unmatched_stops + 1;
                }
            }
            
            write "Arrêts chargés : " + total_bus_stops;
            write "  - Matchés avec routes OSM : " + matched_stops;
            write "  - Non matchés : " + unmatched_stops;
            
        } catch {
            write "⚠️ ERREUR : Impossible de charger " + stops_filename;
            total_bus_stops <- 0;
        }
    }
    
    // CONSTRUCTION MAPPINGS BASIQUES
    action build_basic_mappings {
        write "\n3. CONSTRUCTION MAPPINGS";
        
        // Mapping stopId -> agent
        stopId_to_agent <- map<string, bus_stop>([]);
        ask bus_stop {
            if stopId != nil and stopId != "" {
                stopId_to_agent[stopId] <- self;
            }
        }
        
        // Mapping osmId -> route
        osmId_to_route <- map<string, bus_route>([]);
        ask bus_route {
            if osm_id != nil and osm_id != "" {
                osmId_to_route[osm_id] <- self;
            }
        }
        
        write "Mappings créés :";
        write "  - stopId -> agent : " + length(stopId_to_agent);
        write "  - osmId -> route : " + length(osmId_to_route);
    }
    
    // ==================== SECTION JSON ====================
    
    // TRAITEMENT JSON PRINCIPAL
    action process_json_trips {
        write "\n4. TRAITEMENT DONNÉES JSON";
        
        string json_filename <- stops_folder + "departure_stops_info_stopid.json";
        trip_to_sequence <- map<string, list<pair<string, int>>>([]);
        trip_to_route <- map<string, string>([]);
        collision_check <- map<string, int>([]);
        
        write "→ Lecture du fichier: " + json_filename;
        
        try {
            file json_f <- text_file(json_filename);
            string content <- string(json_f);
            
            map<string, unknown> json_data <- from_json(content);
            
            if !(json_data contains_key "departure_stops_info") {
                write "❌ ERREUR: Clé 'departure_stops_info' manquante";
                return;
            }
            
            list<map<string, unknown>> stops_list <- list<map<string, unknown>>(json_data["departure_stops_info"]);
            write "→ JSON lu: " + length(stops_list) + " arrêts à traiter";
            
            // TRAITER TOUS LES ARRÊTS
            loop stop_index from: 0 to: length(stops_list)-1 {
                map<string, unknown> stop_data <- stops_list[stop_index];
                string current_stop_id <- string(stop_data["stopId"]);
                
                // Vérifier que departureStopsInfo existe
                if !(stop_data contains_key "departureStopsInfo") {
                    continue;
                }
                
                map<string,unknown> subMap <- stop_data["departureStopsInfo"];
                total_stops_processed <- total_stops_processed + 1;
                
                // Ignorer les arrêts sans trips
                if length(subMap.keys) = 0 {
                    continue;
                }
                
                // Messages de progression (moins verbeux)
                if stop_index mod 50 = 0 or stop_index = length(stops_list)-1 {
                    write "→ Progrès: " + (stop_index+1) + "/" + length(stops_list) + " (" + current_stop_id + ")";
                }
                
                // TRAITER TOUS LES TRIPS DE CET ARRÊT
                loop trip_id over: subMap.keys {
                    // Vérifier les collisions de trip_id
                    if collision_check contains_key trip_id {
                        collision_check[trip_id] <- collision_check[trip_id] + 1;
                    } else {
                        collision_check[trip_id] <- 1;
                    }
                    
                    // Éviter de traiter plusieurs fois le même trip
                    if !(trip_to_sequence contains_key trip_id) {
                        do parse_trip_sequence(trip_id, subMap[trip_id]);
                    }
                }
            }
            
            do analyze_json_results;
            do validate_all_trips;
            
        } catch {
            write "❌ ERREUR: Impossible de lire le fichier JSON";
        }
    }
    
    // PARSING SÉQUENCE TRIP (version simplifiée)
    action parse_trip_sequence(string trip_id, unknown raw_data) {
        list<list<string>> sequence <- list<list<string>>(raw_data);
        
        if length(sequence) = 0 {
            return;
        }
        
        list<pair<string, int>> sequence_parsed <- [];
        
        loop stop_time_pair over: sequence {
            if length(stop_time_pair) >= 2 {
                string stop_id <- stop_time_pair[0];
                int time_value <- int(stop_time_pair[1]);
                add pair(stop_id, time_value) to: sequence_parsed;
            }
        }
        
        // Stocker seulement si la séquence parsée n'est pas vide
        if length(sequence_parsed) > 0 {
            trip_to_sequence[trip_id] <- sequence_parsed;
            total_trips_processed <- total_trips_processed + 1;
        }
    }
    
    // ANALYSE RÉSULTATS JSON
    action analyze_json_results {
        write "\n=== RÉSULTATS TRAITEMENT JSON ===";
        
        // Analyse des collisions
        int unique_trips <- length(collision_check.keys where (collision_check[each] = 1));
        int collision_trips <- length(collision_check.keys where (collision_check[each] > 1));
        
        write "→ Arrêts traités: " + total_stops_processed;
        write "→ Trips uniques: " + length(trip_to_sequence.keys);
        write "→ Collisions détectées: " + collision_trips;
        
        // Statistiques des séquences
        if length(trip_to_sequence.keys) > 0 {
            list<int> lengths <- trip_to_sequence.values collect length(each);
            int total_stops_in_sequences <- sum(lengths);
            int min_stops <- min(lengths);
            int max_stops <- max(lengths);
            
            write "→ Total arrêts dans séquences: " + total_stops_in_sequences;
            write "→ Longueur des trajets: " + min_stops + " à " + max_stops + " arrêts";
            
            // Plage temporelle
            list<int> all_times <- [];
            loop trip_sequence over: trip_to_sequence.values {
                if length(trip_sequence) > 0 {
                    add trip_sequence[0].value to: all_times;
                    add trip_sequence[length(trip_sequence)-1].value to: all_times;
                }
            }
            
            if length(all_times) > 0 {
                int min_time <- min(all_times);
                int max_time <- max(all_times);
                write "→ Plage horaire: " + convert_seconds_to_time(min_time) + " → " + convert_seconds_to_time(max_time);
            }
        }
        
        write "=====================================";
    }
    
    // ==================== VÉRIFICATION STRUCTURES ====================
    
    // VÉRIFICATION DES STRUCTURES CHARGÉES
    action verify_data_structures {
        write "\n=== VÉRIFICATION DES STRUCTURES ===";
        
        // 1. VÉRIFICATION TRIP_TO_SEQUENCE
        write "\n1. VÉRIFICATION trip_to_sequence:";
        write "→ Nombre total de trips: " + length(trip_to_sequence.keys);
        
        if length(trip_to_sequence.keys) > 0 {
            write "→ Exemples de trips avec séquences:";
            int count <- 0;
            loop trip_id over: trip_to_sequence.keys {
                if count < 3 {
                    list<pair<string, int>> sequence <- trip_to_sequence[trip_id];
                    write "   • " + trip_id + " (" + length(sequence) + " arrêts):";
                    
                    // Afficher les 3 premiers arrêts
                    int stop_count <- 0;
                    loop stop_time over: sequence {
                        if stop_count < 3 {
                            write "     - " + stop_time.key + " à " + string(stop_time.value);
                            stop_count <- stop_count + 1;
                        } else {
                            break;
                        }
                    }
                    if length(sequence) > 3 {
                        write "     - ... (" + (length(sequence) - 3) + " arrêts supplémentaires)";
                    }
                    count <- count + 1;
                }
            }
        }
        
        // 2. VÉRIFICATION TRIP_TO_ROUTE
        write "\n2. VÉRIFICATION trip_to_route:";
        write "→ Nombre de trips avec routes: " + length(trip_to_route.keys);
        
        // AFFICHER TOUS LES TRIP_TO_ROUTE DANS LA CONSOLE
        write "\n=== CONTENU COMPLET TRIP_TO_ROUTE ===";
        if length(trip_to_route.keys) > 0 {
            loop trip_id over: trip_to_route.keys {
                string route_id <- trip_to_route[trip_id];
                bus_route route_agent <- get_route_by_osm_id(route_id);
                
                string route_info <- route_id;
                if route_agent != nil {
                    route_info <- route_id + " (" + route_agent.route_name + ", " + route_agent.route_type + ")";
                }
                
                write "   • " + trip_id + " → " + route_info;
            }
        } else {
            write "   • Aucun trip avec route trouvé";
        }
        write "=====================================";
        
        if length(trip_to_route.keys) > 0 {
            write "\n→ Exemples de liaisons trip → route (premiers 5):";
            int route_count <- 0;
            loop trip_id over: trip_to_route.keys {
                if route_count < 5 {
                    string route_id <- trip_to_route[trip_id];
                    bus_route route_agent <- get_route_by_osm_id(route_id);
                    
                    string route_info <- route_id;
                    if route_agent != nil {
                        route_info <- route_id + " (" + route_agent.route_name + ", " + route_agent.route_type + ")";
                    }
                    
                    write "   • " + trip_id + " → " + route_info;
                    route_count <- route_count + 1;
                }
            }
        }
        
        write "=====================================";
    }
    
    // ==================== SECTION LIAISON TRIP-ROUTE ====================
    
    // CALCUL ROUTE DOMINANTE POUR CHAQUE TRIP
    action compute_trip_to_route_mappings {
        write "\n=== CALCUL ROUTES DOMINANTES DES TRIPS ===";
        
        int trips_with_routes <- 0;
        int trips_without_routes <- 0;
        int progress_interval <- max(1, length(trip_to_sequence.keys) div 20);
        
        int processed_count <- 0;
        loop trip_id over: trip_to_sequence.keys {
            string dominant_route <- compute_dominant_route_for_trip(trip_id);
            
            if dominant_route != nil and dominant_route != "" {
                trip_to_route[trip_id] <- dominant_route;
                trips_with_routes <- trips_with_routes + 1;
            } else {
                trips_without_routes <- trips_without_routes + 1;
                if debug_mode {
                    write "⚠️ Aucune route dominante trouvée pour trip: " + trip_id;
                }
            }
            
            processed_count <- processed_count + 1;
            if processed_count mod progress_interval = 0 or processed_count = length(trip_to_sequence.keys) {
                write "→ Progrès routes: " + processed_count + "/" + length(trip_to_sequence.keys);
            }
        }
        
        float success_rate <- (trips_with_routes / length(trip_to_sequence.keys)) * 100;
        
        write "→ Trips avec route dominante: " + trips_with_routes + " (" + round(success_rate * 100)/100 + "%)";
        write "→ Trips sans route dominante: " + trips_without_routes;
        write "=====================================";
    }
    
    // FONCTION PRINCIPALE : CALCUL ROUTE DOMINANTE D'UN TRIP
    string compute_dominant_route_for_trip(string trip_id) {
        list<pair<string, int>> sequence <- get_trip_sequence(trip_id);
        
        if length(sequence) = 0 {
            return nil;
        }
        
        // Compteur de fréquence des routes
        map<string, int> route_frequency <- map<string, int>([]);
        int valid_stops <- 0;
        
        // Parcourir tous les arrêts du trip
        loop stop_time over: sequence {
            bus_stop stop_agent <- get_stop_for_trip(stop_time.key);
            
            if stop_agent != nil and stop_agent.closest_route_id != nil and stop_agent.closest_route_id != "" {
                string route_id <- stop_agent.closest_route_id;
                
                if route_frequency contains_key route_id {
                    route_frequency[route_id] <- route_frequency[route_id] + 1;
                } else {
                    route_frequency[route_id] <- 1;
                }
                
                valid_stops <- valid_stops + 1;
            }
        }
        
        // Si aucun arrêt n'a de route associée
        if length(route_frequency.keys) = 0 {
            return nil;
        }
        
        // Trouver la route avec la fréquence maximale
        string dominant_route <- "";
        int max_frequency <- 0;
        
        loop route_id over: route_frequency.keys {
            int frequency <- route_frequency[route_id];
            if frequency > max_frequency {
                max_frequency <- frequency;
                dominant_route <- route_id;
            }
        }
        
        // Debug : afficher les statistiques pour certains trips
        if debug_mode and length(route_frequency.keys) > 1 {
            write "Trip " + trip_id + " routes candidates:";
            loop route_id over: route_frequency.keys {
                write "  - " + route_id + ": " + route_frequency[route_id] + "/" + valid_stops + " arrêts";
            }
            write "  → Dominante: " + dominant_route + " (" + max_frequency + "/" + valid_stops + ")";
        }
        
        return dominant_route;
    }
    
    // ==================== UTILITAIRES ====================
    
    // Conversion secondes -> HH:MM:SS
    string convert_seconds_to_time(int seconds) {
        int hours <- seconds div 3600;
        int minutes <- (seconds mod 3600) div 60;
        int secs <- seconds mod 60;
        
        string h_str <- hours < 10 ? "0" + hours : "" + hours;
        string m_str <- minutes < 10 ? "0" + minutes : "" + minutes;
        string s_str <- secs < 10 ? "0" + secs : "" + secs;
        
        return h_str + ":" + m_str + ":" + s_str;
    }
    
    // APIS D'ACCÈS RÉSEAU
    bus_stop get_stop_agent(string stop_id) {
        if stopId_to_agent contains_key stop_id {
            return stopId_to_agent[stop_id];
        }
        return nil;
    }
    
    bus_route get_route_by_osm_id(string osm_id) {
        if osmId_to_route contains_key osm_id {
            return osmId_to_route[osm_id];
        }
        return nil;
    }
    
    list<bus_stop> get_matched_stops {
        return list<bus_stop>(bus_stop where (each.is_matched));
    }
    
    list<bus_stop> get_unmatched_stops {
        return list<bus_stop>(bus_stop where (!each.is_matched));
    }
    
    // APIS D'ACCÈS TRIPS AVEC LOOKUP AGENTS
    
    // Récupérer agent bus_stop pour un stopId (avec gestion d'erreur)
    bus_stop get_stop_for_trip(string stop_id) {
        if stopId_to_agent contains_key stop_id {
            return stopId_to_agent[stop_id];
        }
        if debug_mode {
            write "⚠️ StopId non trouvé: " + stop_id;
        }
        return nil;
    }
    
    // Récupérer séquence brute d'un trip
    list<pair<string, int>> get_trip_sequence(string trip_id) {
        if trip_to_sequence contains_key trip_id {
            return trip_to_sequence[trip_id];
        }
        return [];
    }
    
    // Récupérer séquence d'agents pour un trip (avec lookup)
    list<pair<bus_stop, int>> get_trip_stops_sequence(string trip_id) {
        list<pair<bus_stop, int>> result <- [];
        
        if !(trip_to_sequence contains_key trip_id) {
            if debug_mode {
                write "⚠️ Trip non trouvé: " + trip_id;
            }
            return result;
        }
        
        list<pair<string, int>> raw_sequence <- trip_to_sequence[trip_id];
        int missing_stops <- 0;
        
        loop stop_time over: raw_sequence {
            bus_stop stop_agent <- get_stop_for_trip(stop_time.key);
            if stop_agent != nil {
                add pair(stop_agent, stop_time.value) to: result;
            } else {
                missing_stops <- missing_stops + 1;
            }
        }
        
        if missing_stops > 0 and debug_mode {
            write "⚠️ Trip " + trip_id + ": " + missing_stops + " arrêts manquants";
        }
        
        return result;
    }
    
    // Valider qu'un trip a tous ses arrêts disponibles
    bool is_trip_valid(string trip_id) {
        if !(trip_to_sequence contains_key trip_id) {
            return false;
        }
        
        list<pair<string, int>> sequence <- trip_to_sequence[trip_id];
        loop stop_time over: sequence {
            if !(stopId_to_agent contains_key stop_time.key) {
                return false;
            }
        }
        return true;
    }
    
    // Obtenir premier arrêt (agent) d'un trip pour spawn véhicule
    bus_stop get_trip_departure_stop(string trip_id) {
        list<pair<string, int>> sequence <- get_trip_sequence(trip_id);
        if length(sequence) > 0 {
            return get_stop_for_trip(sequence[0].key);
        }
        return nil;
    }
    
    // Obtenir dernier arrêt (agent) d'un trip
    bus_stop get_trip_arrival_stop(string trip_id) {
        list<pair<string, int>> sequence <- get_trip_sequence(trip_id);
        if length(sequence) > 0 {
            return get_stop_for_trip(sequence[length(sequence)-1].key);
        }
        return nil;
    }
    
    // Obtenir prochain arrêt dans un trip à partir d'un index
    bus_stop get_next_stop_in_trip(string trip_id, int current_index) {
        list<pair<string, int>> sequence <- get_trip_sequence(trip_id);
        if current_index + 1 < length(sequence) {
            return get_stop_for_trip(sequence[current_index + 1].key);
        }
        return nil; // Fin du trip
    }
    
    // APIS D'ACCÈS TRIPS-ROUTES
    
    // Obtenir la route OSM dominante d'un trip
    string get_trip_dominant_route(string trip_id) {
        if trip_to_route contains_key trip_id {
            return trip_to_route[trip_id];
        }
        return nil;
    }
    
    // Obtenir l'agent bus_route d'un trip
    bus_route get_trip_route_agent(string trip_id) {
        string osm_id <- get_trip_dominant_route(trip_id);
        if osm_id != nil {
            return get_route_by_osm_id(osm_id);
        }
        return nil;
    }
    
    // Obtenir tous les trips qui utilisent une route donnée
    list<string> get_trips_using_route(string osm_id) {
        list<string> result <- [];
        loop trip_id over: trip_to_route.keys {
            if trip_to_route[trip_id] = osm_id {
                add trip_id to: result;
            }
        }
        return result;
    }
    
    // Vérifier si un trip a une route assignée
    bool trip_has_route(string trip_id) {
        return trip_to_route contains_key trip_id and trip_to_route[trip_id] != nil and trip_to_route[trip_id] != "";
    }
    
    // Obtenir tous les trips avec route assignée
    list<string> get_trips_with_routes {
        list<string> result <- [];
        loop trip_id over: trip_to_sequence.keys {
            if trip_has_route(trip_id) {
                add trip_id to: result;
            }
        }
        return result;
    }
    
    // Statistiques des routes utilisées par les trips
    map<string, int> get_route_usage_statistics {
        map<string, int> usage <- map<string, int>([]);
        
        loop trip_id over: trip_to_route.keys {
            string route_id <- trip_to_route[trip_id];
            if route_id != nil and route_id != "" {
                if usage contains_key route_id {
                    usage[route_id] <- usage[route_id] + 1;
                } else {
                    usage[route_id] <- 1;
                }
            }
        }
        
        return usage;
    }
    
    // API COMBINÉE : Informations complètes d'un trip
    map<string, unknown> get_trip_complete_info(string trip_id) {
        map<string, unknown> info <- map<string, unknown>([]);
        
        info["trip_id"] <- trip_id;
        info["sequence"] <- get_trip_sequence(trip_id);
        info["departure_stop"] <- get_trip_departure_stop(trip_id);
        info["arrival_stop"] <- get_trip_arrival_stop(trip_id);
        info["dominant_route_id"] <- get_trip_dominant_route(trip_id);
        info["route_agent"] <- get_trip_route_agent(trip_id);
        info["is_valid"] <- is_trip_valid(trip_id);
        info["has_route"] <- trip_has_route(trip_id);
        
        // Statistiques
        list<pair<string, int>> sequence <- get_trip_sequence(trip_id);
        if length(sequence) > 0 {
            info["nb_stops"] <- length(sequence);
            info["duration_seconds"] <- sequence[length(sequence)-1].value - sequence[0].value;
            info["departure_time"] <- sequence[0].value;
            info["arrival_time"] <- sequence[length(sequence)-1].value;
        }
        
        return info;
    }
    
    // UTILITAIRES POUR SIMULATION
    
    list<string> get_all_trip_ids {
        return trip_to_sequence.keys;
    }
    
    // Obtenir tous les trips valides (avec tous les arrêts disponibles)
    list<string> get_valid_trip_ids {
        list<string> valid_trips <- [];
        loop trip_id over: trip_to_sequence.keys {
            if is_trip_valid(trip_id) {
                add trip_id to: valid_trips;
            }
        }
        return valid_trips;
    }
    
    // Statistiques de validation des trips
    action validate_all_trips {
        write "\n=== VALIDATION DES TRIPS ===";
        
        int valid_trips <- 0;
        int invalid_trips <- 0;
        int total_missing_stops <- 0;
        
        loop trip_id over: trip_to_sequence.keys {
            bool is_valid <- true;
            int missing_in_trip <- 0;
            
            list<pair<string, int>> sequence <- trip_to_sequence[trip_id];
            loop stop_time over: sequence {
                if !(stopId_to_agent contains_key stop_time.key) {
                    is_valid <- false;
                    missing_in_trip <- missing_in_trip + 1;
                    total_missing_stops <- total_missing_stops + 1;
                }
            }
            
            if is_valid {
                valid_trips <- valid_trips + 1;
            } else {
                invalid_trips <- invalid_trips + 1;
                if debug_mode {
                    write "Trip " + trip_id + ": " + missing_in_trip + " arrêts manquants";
                }
            }
        }
        
        float valid_percentage <- (valid_trips / length(trip_to_sequence.keys)) * 100;
        
        write "→ Trips valides: " + valid_trips + " (" + round(valid_percentage * 100)/100 + "%)";
        write "→ Trips invalides: " + invalid_trips;
        write "→ StopIds manquants total: " + total_missing_stops;
        write "=====================================";
    }
}

// AGENTS
species bus_route {
    string route_name;
    string osm_id;
    string route_type;
    string highway_type;
    float length_meters;
    
    aspect default {
        if shape != nil {
            rgb route_color <- #lightgray;  // Couleur par défaut : gris clair
            int route_width <- 1;
            
            // ROUTE MISE EN ÉVIDENCE POUR TRIP 01_1_MD_14
            if osm_id = highlighted_route_osm_id and highlighted_route_osm_id != "" {
                route_color <- #red;      // Rouge pour la route du trip 01_1_MD_14
                route_width <- 8;         // Plus épais pour bien la voir
            } else {
                // Couleurs normales pour les autres routes selon leur type
                if route_type = "bus" {
                    route_color <- #blue;
                    route_width <- 2;
                } else if route_type = "tram" {
                    route_color <- #orange;
                    route_width <- 2;
                } else if route_type = "subway" {
                    route_color <- #purple;
                    route_width <- 2;
                }
            }
            
            draw shape color: route_color width: route_width;
        }
    }
    
    aspect detailed {
        if shape != nil {
            rgb route_color <- #blue;
            if route_type = "bus" {
                route_color <- #blue;
            } else if route_type = "tram" {
                route_color <- #orange;
            } else if route_type = "subway" {
                route_color <- #purple;
            } else {
                route_color <- #gray;
            }
            draw shape color: route_color width: 3;
        }
    }
}

species bus_stop {
    string stopId <- "";
    string stop_name <- "";
    string closest_route_id <- "";
    float closest_route_dist <- -1.0;
    bool is_matched <- false;
    string is_matched_str <- "FALSE";
    
    aspect default {
        rgb stop_color <- is_matched ? #green : #red;
        draw circle(100.0) color: stop_color;
    }
    
    aspect detailed {
        rgb stop_color <- is_matched ? #green : #red;
        draw circle(120.0) color: stop_color;
        
        if is_matched {
            draw circle(160.0) border: #darkgreen width: 2;
        }
        
        if stop_name != nil and stop_name != "" {
            draw stop_name at: location + {0, 200} color: #black size: 10;
        }
        
        if stopId != nil and stopId != "" {
            draw stopId at: location + {0, -200} color: #gray size: 8;
        }
        
        if is_matched and closest_route_dist > 0 {
            draw string(int(closest_route_dist)) + "m" at: location + {0, 220} color: #blue size: 8;
        }
    }
    
    aspect minimal {
        rgb stop_color <- is_matched ? #green : #red;
        draw circle(80.0) color: stop_color;
    }
}

// EXPERIMENT
experiment combined_network type: gui {
    parameter "Debug Mode" var: debug_mode category: "Configuration";
    
    action reload_all {
        ask world {
            // Nettoyer les agents
            ask bus_route { do die; }
            ask bus_stop { do die; }
            
            // Réinitialiser les variables
            total_bus_routes <- 0;
            total_bus_stops <- 0;
            matched_stops <- 0;
            unmatched_stops <- 0;
            total_stops_processed <- 0;
            total_trips_processed <- 0;
            highlighted_route_osm_id <- "";
            highlighted_route_agent <- nil;
            
            // Réinitialiser les structures
            stopId_to_agent <- map<string, bus_stop>([]);
            osmId_to_route <- map<string, bus_route>([]);
            trip_to_sequence <- map<string, list<pair<string, int>>>([]);
            trip_to_route <- map<string, string>([]);
            collision_check <- map<string, int>([]);
            
            // Recharger tout
            do load_bus_network;
            do load_gtfs_stops;
            do build_basic_mappings;
            do process_json_trips;
            do compute_trip_to_route_mappings;
            do highlight_trip_route;
        }
    }
    
    user_command "Recharger Tout" action: reload_all;
    
    output {
        display "Réseau Bus Combiné" background: #white type: 2d {
            species bus_route aspect: default;
            species bus_stop aspect: default;
        }
        
        monitor "Routes OSM" value: total_bus_routes;
        monitor "Arrêts GTFS" value: total_bus_stops;
        monitor "Arrêts matchés" value: matched_stops;
        monitor "Trips JSON" value: length(trip_to_sequence.keys);
        monitor "Trips avec routes" value: length(trip_to_route.keys);
        monitor "Route Trip 01_1_MD_14" value: highlighted_route_osm_id != "" ? highlighted_route_osm_id : "Non trouvée";
        monitor "Nom Route Highlighted" value: highlighted_route_agent != nil ? highlighted_route_agent.route_name : "N/A";
        monitor "Taux trip-route %" value: length(trip_to_sequence.keys) > 0 ? round((length(trip_to_route.keys) / length(trip_to_sequence.keys)) * 10000) / 100 : 0;
        monitor "Arrêts JSON traités" value: total_stops_processed;
        monitor "Moyenne arrêts/trip" value: length(trip_to_sequence.keys) > 0 ? round((sum(trip_to_sequence.values collect length(each)) / length(trip_to_sequence.keys)) * 100) / 100 : 0;
    }
}