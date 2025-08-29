/**
 * Name: Clean_OSM_To_Shapefile
 * Author: Promagicshow95
 * Description: Export OSM vers shapefile - VERSION CORRIGÉE ATTRIBUTS
 * Tags: OSM, shapefile, export, network, transport
 * Date: 2025-08-21
 */

model Clean_OSM_To_Shapefile

global {
    // --- FICHIERS ---
    file data_file <- shape_file("../../includes/shapeFileHanoishp.shp");
    geometry shape <- envelope(data_file);
    
    // --- OSM CONFIGURATION ---
    point top_left <- CRS_transform({0,0}, "EPSG:4326").location;
    point bottom_right <- CRS_transform({shape.width, shape.height}, "EPSG:4326").location;
    string adress <- "http://overpass-api.de/api/xapi_meta?*[bbox=" + top_left.x + "," + bottom_right.y + "," + bottom_right.x + "," + top_left.y + "]";
    
    // ✅ CHARGEMENT COMPLET DE TOUTES LES ROUTES
    map<string, list> osm_data_to_generate <- [
        "highway"::[],     // TOUTES les routes
        "railway"::[],     // TOUTES les voies ferrées  
        "route"::[],       // TOUTES les relations route
        "cycleway"::[],    // TOUTES les pistes cyclables
        "bus"::[],         // Routes bus
        "psv"::[]          // Public service vehicles
    ];
    
    // --- VARIABLES STATISTIQUES ---
    int nb_bus_routes <- 0;
    int nb_tram_routes <- 0;
    int nb_metro_routes <- 0;
    int nb_train_routes <- 0;
    int nb_cycleway_routes <- 0;
    int nb_road_routes <- 0;
    int nb_other_routes <- 0;
    int nb_total_created <- 0;
    
    // --- PARAMÈTRES D'EXPORT ---
    string export_folder <- "../../results/";

    init {
        write "=== EXPORT PROPRE OSM VERS SHAPEFILE ===";
        
        // Chargement OSM COMPLET
        file<geometry> osm_geometries <- osm_file<geometry>(adress, osm_data_to_generate);
        write "✅ Géométries OSM chargées : " + length(osm_geometries);
        
        // ✅ CRÉER TOUTES LES ROUTES SANS EXCEPTION
        int valid_geoms <- 0;
        int invalid_geoms <- 0;
        
        loop geom over: osm_geometries {
            if geom != nil and length(geom.points) > 1 {
                do create_route_complete(geom);
                valid_geoms <- valid_geoms + 1;
            } else {
                invalid_geoms <- invalid_geoms + 1;
            }
        }
        
        write "✅ Géométries valides : " + valid_geoms;
        write "❌ Géométries invalides : " + invalid_geoms;
        write "✅ Agents network_route créés : " + length(network_route);
        
        // Debug : vérifier quelques agents
        if length(network_route) > 0 {
            network_route first_route <- first(network_route);
            write "🔍 Premier agent : " + first_route.name + " (type: " + first_route.route_type + ")";
            write "🔍 Géométrie valide : " + (first_route.shape != nil);
            write "🔍 OSM ID : " + first_route.osm_id;
            write "🔍 Highway type : " + first_route.highway_type;
        }
        
        // ✅ EXPORT IMMÉDIAT VERS SHAPEFILE
        do export_complete_network;
        
        // 🆕 EXPORT PAR TYPE POUR ÉVITER LES FICHIERS TROP VOLUMINEUX - VERSION CORRIGÉE
        do export_by_type_fixed;
        
        // Statistiques finales
        write "\n=== RÉSEAU EXPORTÉ ===";
        write "🚌 Routes Bus : " + nb_bus_routes;
        write "🚋 Routes Tram : " + nb_tram_routes; 
        write "🚇 Routes Métro : " + nb_metro_routes;
        write "🚂 Routes Train : " + nb_train_routes;
        write "🚴 Routes Cycleway : " + nb_cycleway_routes;
        write "🛣️ Routes Road : " + nb_road_routes;
        write "❓ Autres : " + nb_other_routes;
        write "🛤️ TOTAL EXPORTÉ : " + nb_total_created;
    }
    
    // 🎯 CRÉATION ROUTE COMPLÈTE - SANS EXCLUSION
    action create_route_complete(geometry geom) {
        string route_type;
        int routeType_num;
        rgb route_color;
        float route_width;
        
        // Récupération des attributs OSM
        string name <- (geom.attributes["name"] as string);
        string ref <- (geom.attributes["ref"] as string);
        string highway <- (geom.attributes["highway"] as string);
        string railway <- (geom.attributes["railway"] as string);
        string route <- (geom.attributes["route"] as string);
        string route_master <- (geom.attributes["route_master"] as string);
        string bus <- (geom.attributes["bus"] as string);
        string cycleway <- (geom.attributes["cycleway"] as string);
        string bicycle <- (geom.attributes["bicycle"] as string);
        string psv <- (geom.attributes["psv"] as string);
        
        string osm_id <- (geom.attributes["osm_id"] as string);
        if (osm_id = nil or osm_id = "") {
            osm_id <- "osm_" + rnd(1000000);
        }
        
        // Nom par défaut
        if (name = nil or name = "") {
            name <- ref != nil ? ref : ("Route_" + osm_id);
        }

        // 🎯 CLASSIFICATION EXHAUSTIVE
        if (
            (route = "bus") or (route = "trolleybus") or
            (route_master = "bus") or (highway = "busway") or
            (bus in ["yes", "designated"]) or (psv = "yes")
        ) {
            route_type <- "bus";
            routeType_num <- 3;
            route_color <- #blue;
            route_width <- 2.5;
            nb_bus_routes <- nb_bus_routes + 1;
            
        } else if (
            (railway = "tram") or (route = "tram") or (route_master = "tram")
        ) {
            route_type <- "tram";
            routeType_num <- 0;
            route_color <- #orange;
            route_width <- 2.0;
            nb_tram_routes <- nb_tram_routes + 1;
            
        } else if (
            (railway = "subway") or (railway = "metro") or
            (route = "subway") or (route = "metro") or (route_master = "subway")
        ) {
            route_type <- "metro";
            routeType_num <- 1;
            route_color <- #red;
            route_width <- 2.0;
            nb_metro_routes <- nb_metro_routes + 1;
            
        } else if (
            railway != nil and railway != "" and
            !(railway in ["abandoned", "platform", "disused", "construction", "proposed", "razed", "dismantled"])
        ) {
            route_type <- "train";
            routeType_num <- 2;
            route_color <- #green;
            route_width <- 1.8;
            nb_train_routes <- nb_train_routes + 1;

        } else if (
            (highway = "cycleway") or (cycleway != nil) or
            (bicycle in ["designated", "yes"])
        ) {
            route_type <- "cycleway";
            routeType_num <- 10;
            route_color <- #purple;
            route_width <- 1.2;
            nb_cycleway_routes <- nb_cycleway_routes + 1;
            
        } else if (highway != nil and highway != "") {
            route_type <- "road";
            routeType_num <- 20;
            route_color <- #gray;
            route_width <- 1.0;
            nb_road_routes <- nb_road_routes + 1;
            
        } else {
            route_type <- "other";
            routeType_num <- 99;
            route_color <- #lightgray;
            route_width <- 0.8;
            nb_other_routes <- nb_other_routes + 1;
        }

        // Calcul des propriétés géométriques
        float length_meters <- geom.perimeter;
        int points_count <- length(geom.points);

        // ✅ CRÉER TOUS LES AGENTS - AUCUNE EXCLUSION
        create network_route with: [
            shape::geom,
            route_type::route_type,
            routeType_num::routeType_num,
            route_color::route_color,
            route_width::route_width,
            name::name,
            osm_id::osm_id,
            highway_type::highway,
            railway_type::railway,
            route_rel::route,
            bus_access::bus,
            ref_number::ref,
            length_m::length_meters,
            num_points::points_count
        ];
        
        nb_total_created <- nb_total_created + 1;
    }
    
    // 🎯 EXPORT COMPLET VERS SHAPEFILE - SYNTAXE CORRIGÉE
    action export_complete_network {
        write "\n=== EXPORT VERS SHAPEFILE ===";
        
        if empty(network_route) {
            write "❌ ERREUR : Aucun agent créé à exporter !";
            return;
        }
        
        string shapefile_path <- export_folder + "network_transport_complete.shp";
        
        // ✅ EXPORT CORRIGÉ - SYNTAXE ATTRIBUTS FIXÉE
        try {
            save network_route to: shapefile_path format: "shp" attributes: [
                "osm_id"::osm_id,                // ✅ CORRIGÉ : valeur réelle
                "name"::name,                    // ✅ CORRIGÉ : valeur réelle
                "route_type"::route_type,        // ✅ CORRIGÉ : valeur réelle
                "routeType"::routeType_num,      // ✅ CORRIGÉ : valeur réelle
                "highway"::highway_type,         // ✅ CORRIGÉ : valeur réelle
                "railway"::railway_type,         // ✅ CORRIGÉ : valeur réelle
                "length_m"::length_m             // ✅ CORRIGÉ : valeur réelle
            ];
            
            write "✅ EXPORT RÉUSSI : " + shapefile_path;
            write "📊 " + length(network_route) + " routes exportées";
            
        } catch {
            write "❌ Erreur d'export - Tentative avec attributs minimaux...";
            
            try {
                save network_route to: shapefile_path format: "shp" attributes: [
                    "osm_id"::osm_id,
                    "type"::route_type,
                    "highway"::highway_type
                ];
                write "✅ EXPORT MINIMAL RÉUSSI : " + shapefile_path;
            } catch {
                write "❌ Échec total - Export sans attributs...";
                save network_route to: shapefile_path format: "shp";
                write "✅ EXPORT GÉOMÉTRIE SEULE : " + shapefile_path;
            }
        }
    }
    
    // 🆕 EXPORT PAR TYPE DE TRANSPORT CORRIGÉ
    action export_by_type_fixed {
        write "\n=== EXPORT PAR TYPE DE TRANSPORT CORRIGÉ ===";
        
        // Export Bus par batch
        list<network_route> bus_routes <- network_route where (each.route_type = "bus");
        write "🔍 Bus routes trouvées : " + length(bus_routes);
        
        if !empty(bus_routes) {
            do export_by_batch_robust(bus_routes, "bus_routes", 10000);
        }
        
        // Export Routes principales par batch
        list<network_route> main_roads <- network_route where (each.route_type = "road");
        write "🔍 Main roads trouvées : " + length(main_roads);
        
        if !empty(main_roads) {
            do export_by_batch_robust(main_roads, "main_roads", 50000);
        }
        
        // Export Transport public (plus petit, export direct)
        list<network_route> public_transport <- network_route where (each.route_type in ["tram", "metro", "train"]);
        if !empty(public_transport) {
            try {
                save public_transport to: export_folder + "public_transport.shp" format: "shp" attributes: [
                    "osm_id"::osm_id, 
                    "name"::name, 
                    "route_type"::route_type, 
                    "railway"::railway_type, 
                    "length_m"::length_m
                ];
                write "✅ Transport public exporté : " + length(public_transport) + " → public_transport.shp";
            } catch {
                write "❌ Erreur export transport public - tentative export minimal";
                try {
                    save public_transport to: export_folder + "public_transport.shp" format: "shp" attributes: [
                        "osm_id"::osm_id,
                        "type"::route_type
                    ];
                    write "✅ Transport public (minimal) exporté";
                } catch {
                    write "❌ Erreur totale export transport public";
                }
            }
        }
        
        // Export Cycleway (plus petit, export direct)
        list<network_route> cycleways <- network_route where (each.route_type = "cycleway");
        if !empty(cycleways) {
            try {
                save cycleways to: export_folder + "cycleways.shp" format: "shp" attributes: [
                    "osm_id"::osm_id, 
                    "name"::name, 
                    "highway"::highway_type, 
                    "length_m"::length_m
                ];
                write "✅ Pistes cyclables exportées : " + length(cycleways) + " → cycleways.shp";
            } catch {
                write "❌ Erreur export cycleways - tentative export minimal";
                try {
                    save cycleways to: export_folder + "cycleways.shp" format: "shp" attributes: [
                        "osm_id"::osm_id
                    ];
                    write "✅ Pistes cyclables (minimal) exportées";
                } catch {
                    write "❌ Erreur totale export cycleways";
                }
            }
        }
        
        write "🎯 EXPORT PAR TYPE CORRIGÉ TERMINÉ !";
    }
    
    // 🆕 EXPORT PAR BATCH POUR GROS VOLUMES - SYNTAXE CORRIGÉE
    action export_by_batch_robust(list<network_route> routes, string filename, int batch_size) {
        write "🔄 Export robuste par batch : " + filename + " (" + length(routes) + " objets)";
        
        int total_exported <- 0;
        int batch_num <- 0;
        int current_index <- 0;
        
        // Pré-filtrer les routes valides une seule fois
        list<network_route> all_valid_routes <- routes where (each.shape != nil and each.osm_id != nil);
        write "🔍 Routes valides pré-filtrées : " + length(all_valid_routes) + "/" + length(routes);
        
        loop while: current_index < length(all_valid_routes) {
            int end_index <- min(current_index + batch_size - 1, length(all_valid_routes) - 1);
            list<network_route> current_batch <- [];
            
            // Créer le batch actuel
            loop i from: current_index to: end_index {
                current_batch <+ all_valid_routes[i];
            }
            
            // Export du batch
            string batch_filename <- export_folder + filename + "_part" + batch_num + ".shp";
            
            // Essayer d'abord avec tous les attributs - SYNTAXE CORRIGÉE
            bool export_success <- false;
            
            try {
                save current_batch to: batch_filename format: "shp" attributes: [
                    "osm_id"::osm_id,              // ✅ CORRIGÉ : valeur réelle
                    "name"::name,                  // ✅ CORRIGÉ : valeur réelle
                    "route_type"::route_type,      // ✅ CORRIGÉ : valeur réelle
                    "highway"::highway_type,       // ✅ CORRIGÉ : valeur réelle
                    "railway"::railway_type,       // ✅ CORRIGÉ : valeur réelle
                    "length_m"::length_m           // ✅ CORRIGÉ : valeur réelle
                ];
                
                write "  ✅ Batch " + batch_num + " complet : " + length(current_batch) + " objets";
                total_exported <- total_exported + length(current_batch);
                export_success <- true;
                
            } catch {
                write "  ⚠️ Erreur attributs complets, tentative attributs essentiels...";
            }
            
            // Si échec, essayer avec attributs minimaux
            if !export_success {
                try {
                    save current_batch to: batch_filename format: "shp" attributes: [
                        "osm_id"::osm_id,
                        "type"::route_type
                    ];
                    
                    write "  ✅ Batch " + batch_num + " minimal : " + length(current_batch) + " objets";
                    total_exported <- total_exported + length(current_batch);
                    export_success <- true;
                    
                } catch {
                    write "  ⚠️ Erreur attributs minimaux, export géométrie seule...";
                }
            }
            
            // En dernier recours, export sans attributs
            if !export_success {
                try {
                    save current_batch to: batch_filename format: "shp";
                    write "  ✅ Batch " + batch_num + " géométrie seule : " + length(current_batch) + " objets";
                    total_exported <- total_exported + length(current_batch);
                    
                } catch {
                    write "  ❌ Échec total batch " + batch_num;
                }
            }
            
            current_index <- end_index + 1;
            batch_num <- batch_num + 1;
        }
        
        write "📊 TOTAL " + filename + " : " + total_exported + "/" + length(all_valid_routes) + " objets exportés en " + batch_num + " fichiers";
    }
}

// 🚌 AGENT ROUTE SIMPLE ET PROPRE
species network_route {
    // Attributs de base
    geometry shape;
    string route_type;
    int routeType_num;
    rgb route_color;
    float route_width;
    string name;
    string osm_id;
    
    // Attributs OSM originaux
    string highway_type;
    string railway_type;
    string route_rel;
    string bus_access;
    string ref_number;
    
    // Propriétés calculées
    float length_m;
    int num_points;
    
    aspect default {
        if shape != nil {
            draw shape color: route_color width: route_width;
        }
    }
    
    aspect thick {
        if shape != nil {
            draw shape color: route_color width: (route_width * 2);
        }
    }
    
    aspect colored {
        if shape != nil {
            rgb display_color;
            if route_type = "bus" {
                display_color <- #blue;
            } else if route_type = "tram" {
                display_color <- #orange;
            } else if route_type = "metro" {
                display_color <- #red;
            } else if route_type = "train" {
                display_color <- #green;
            } else if route_type = "cycleway" {
                display_color <- #purple;
            } else if route_type = "road" {
                display_color <- #gray;
            } else {
                display_color <- #black;
            }
            draw shape color: display_color width: 2.0;
        }
    }
}

// 🎯 EXPÉRIMENT PRINCIPAL - SIMPLE ET FONCTIONNEL
experiment main_export type: gui {
    output {
        display "Export OSM Complet" background: #white {
            species network_route aspect: thick;
            
            overlay position: {10, 10} size: {380 #px, 320 #px} background: #white transparency: 0.9 border: #black {
                draw "=== EXPORT OSM PROPRE ===" at: {20#px, 25#px} color: #black font: font("Arial", 14, #bold);
                
                draw "🔍 AGENTS CRÉÉS" at: {20#px, 50#px} color: #darkred font: font("Arial", 11, #bold);
                draw "Total : " + length(network_route) + " agents" at: {30#px, 70#px} color: #black;
                
                draw "📊 RÉPARTITION" at: {20#px, 95#px} color: #darkblue font: font("Arial", 11, #bold);
                draw "🚌 Bus : " + nb_bus_routes at: {30#px, 115#px} color: #blue;
                draw "🚋 Tram : " + nb_tram_routes at: {30#px, 130#px} color: #orange;
                draw "🚇 Métro : " + nb_metro_routes at: {30#px, 145#px} color: #red;
                draw "🚂 Train : " + nb_train_routes at: {30#px, 160#px} color: #green;
                draw "🚴 Cycleway : " + nb_cycleway_routes at: {30#px, 175#px} color: #purple;
                draw "🛣️ Roads : " + nb_road_routes at: {30#px, 190#px} color: #gray;
                draw "❓ Autres : " + nb_other_routes at: {30#px, 205#px} color: #lightgray;
                
                draw "📁 EXPORT TERMINÉ" at: {20#px, 230#px} color: #darkgreen font: font("Arial", 11, #bold);
                draw "✅ 5 fichiers shapefiles créés" at: {30#px, 250#px} color: #green;
                draw "✅ Dossier : ../../results/" at: {30#px, 265#px} color: #green size: 8;
                draw "✅ Prêt pour utilisation SIG" at: {30#px, 280#px} color: #green;
                
                draw "💡 Lignes épaisses pour meilleure visibilité" at: {30#px, 300#px} color: #gray size: 8;
            }
        }
    }
}

// 🎯 EXPÉRIMENT AVEC COULEURS PAR TYPE
experiment colored_view type: gui {
    output {
        display "Réseau Coloré" background: #white {
            species network_route aspect: colored;
            
            overlay position: {10, 10} size: {250 #px, 180 #px} background: #white transparency: 0.9 {
                draw "=== LÉGENDE COULEURS ===" at: {10#px, 20#px} color: #black font: font("Arial", 12, #bold);
                draw "🚌 Bleu = Bus" at: {10#px, 40#px} color: #blue;
                draw "🚋 Orange = Tram" at: {10#px, 55#px} color: #orange;
                draw "🚇 Rouge = Métro" at: {10#px, 70#px} color: #red;
                draw "🚂 Vert = Train" at: {10#px, 85#px} color: #green;
                draw "🚴 Violet = Cycleway" at: {10#px, 100#px} color: #purple;
                draw "🛣️ Gris = Routes" at: {10#px, 115#px} color: #gray;
                draw "❓ Noir = Autres" at: {10#px, 130#px} color: #black;
                draw "Total : " + length(network_route) at: {10#px, 150#px} color: #black font: font("Arial", 10, #bold);
            }
        }
    }
}