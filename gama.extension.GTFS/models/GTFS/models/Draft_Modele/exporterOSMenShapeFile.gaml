/**
 * Name: OSM_Bus_Complete_Export
 * Description: Visualisation + Export robuste des routes OSM (logique Clean_OSM)
 * Tags: OSM, bus, export, shapefile, robust
 * Date: 2025-11-18
 */

model OSM_Bus_Complete_Export

global {
    // --- FICHIERS ---
    file data_file <- shape_file("../../includes/shapeFileNantes.shp");
    geometry shape <- envelope(data_file);
    
    // --- OSM CONFIGURATION ---
    point top_left <- CRS_transform({0,0}, "EPSG:4326").location;
    point bottom_right <- CRS_transform({shape.width, shape.height}, "EPSG:4326").location;
    string adress <- "http://overpass-api.de/api/xapi_meta?*[bbox=" + top_left.x + "," + bottom_right.y + "," + bottom_right.x + "," + top_left.y + "]";
    
    // ✅ CHARGEMENT ROUTES POUR BUS ET TRANSPORT PUBLIC
    map<string, list> osm_data_to_generate <- [
        "highway"::[],
        "railway"::[],
        "route"::[],
        "bus"::[],
        "psv"::[]
    ];
    
    // --- VARIABLES STATISTIQUES ---
    int nb_bus_routes <- 0;
    int nb_tram_routes <- 0;
    int nb_metro_routes <- 0;
    int nb_train_routes <- 0;
    int nb_other_routes <- 0;
    int nb_total_created <- 0;
    int nb_without_osm_id <- 0;
    
    // --- EXPORT ---
    string export_folder <- "../../results2/";

    init {
        write "=== 🚌 VISUALISATION + EXPORT ROUTES OSM ===\n";
        
        // Chargement OSM depuis API
        file<geometry> osm_geometries <- osm_file<geometry>(adress, osm_data_to_generate);
        write "✅ Géométries OSM chargées : " + length(osm_geometries);
        
        // Créer les routes (logique Clean_OSM)
        int valid_geoms <- 0;
        int invalid_geoms <- 0;
        
        loop geom over: osm_geometries {
            if geom != nil and length(geom.points) > 1 {
                do create_route_complete(geom);  // ✅ Nom de l'action comme Clean_OSM
                valid_geoms <- valid_geoms + 1;
            } else {
                invalid_geoms <- invalid_geoms + 1;
            }
        }
        
        write "\n=== 📊 RÉSULTATS CHARGEMENT ===";
        write "✅ Géométries valides : " + valid_geoms;
        write "❌ Géométries invalides : " + invalid_geoms;
        write "✅ Agents créés : " + length(network_route);
        write "⚠️ Routes sans ID OSM : " + nb_without_osm_id;
        
        // Statistiques par type
        write "\n=== 📈 RÉPARTITION PAR TYPE ===";
        write "🚌 Routes Bus : " + nb_bus_routes;
        write "🚋 Routes Tram : " + nb_tram_routes;
        write "🚇 Routes Métro : " + nb_metro_routes;
        write "🚂 Routes Train : " + nb_train_routes;
        write "❓ Autres : " + nb_other_routes;
        write "━━━━━━━━━━━━━━━━━━━━━━━━━";
        write "🛤️ TOTAL : " + nb_total_created;
        
        // ✅ EXPORT AVEC LOGIQUE ROBUSTE (comme Clean_OSM)
        write "\n=== 📦 DÉBUT EXPORT SHAPEFILE ===";
        do export_complete_network;
        do export_by_type_fixed;
        write "=== ✅ EXPORT TERMINÉ ===\n";
    }
    
    // ══════════════════════════════════════════════════════════
    // 🎯 CRÉATION ROUTE COMPLÈTE (LOGIQUE CLEAN_OSM)
    // ══════════════════════════════════════════════════════════
    action create_route_complete(geometry geom) {
        string route_type;
        int routeType_num;
        rgb route_color;
        float route_width;
        
        // ────────────────────────────────────────────────────────
        // 📥 RÉCUPÉRATION ATTRIBUTS OSM
        // ────────────────────────────────────────────────────────
        string name <- (geom.attributes["name"] as string);
        string ref <- (geom.attributes["ref"] as string);
        string highway <- (geom.attributes["highway"] as string);
        string railway <- (geom.attributes["railway"] as string);
        string route <- (geom.attributes["route"] as string);
        string route_master <- (geom.attributes["route_master"] as string);
        string bus <- (geom.attributes["bus"] as string);
        string psv <- (geom.attributes["psv"] as string);
        
        // ────────────────────────────────────────────────────────
        // 🔑 RÉCUPÉRATION ID OSM (LOGIQUE ROBUSTE CLEAN_OSM)
        // ────────────────────────────────────────────────────────
        string id_str <- (geom.attributes["@id"] as string);
        if (id_str = nil or id_str = "") { 
            id_str <- (geom.attributes["id"] as string); 
        }
        if (id_str = nil or id_str = "") { 
            id_str <- (geom.attributes["osm_id"] as string); 
        }
        if (id_str = nil or id_str = "") { 
            id_str <- (geom.attributes["way_id"] as string); 
        }
        if (id_str = nil or id_str = "") { 
            id_str <- (geom.attributes["rel_id"] as string); 
        }
        if (id_str = nil or id_str = "") { 
            id_str <- (geom.attributes["relation_id"] as string); 
        }
        
        // ────────────────────────────────────────────────────────
        // 🏷️ DÉTERMINATION TYPE OSM
        // ────────────────────────────────────────────────────────
        string osm_type <- (geom.attributes["@type"] as string);
        if (osm_type = nil or osm_type = "") { 
            osm_type <- (geom.attributes["type"] as string); 
        }
        
        if (osm_type = nil or osm_type = "") {
            if (route != nil and route != "") {
                osm_type <- "relation";
            } else if (highway != nil or railway != nil) {
                osm_type <- "way";
            } else {
                osm_type <- "way";
            }
        }
        
        // ────────────────────────────────────────────────────────
        // 🔑 CONSTRUCTION ID CANONIQUE (CLEF CLEAN_OSM)
        // ────────────────────────────────────────────────────────
        string osm_uid <- "";
        if (id_str != nil and id_str != "") {
            osm_uid <- osm_type + ":" + id_str;  // Format: "way:123456"
        } else {
            nb_without_osm_id <- nb_without_osm_id + 1;
            osm_uid <- "";  // ✅ Pas d'ID aléatoire !
        }
        
        // ────────────────────────────────────────────────────────
        // 📛 NOM PAR DÉFAUT INTELLIGENT
        // ────────────────────────────────────────────────────────
        if (name = nil or name = "") {
            if (ref != nil and ref != "") {
                name <- ref;
            } else if (id_str != nil and id_str != "") {
                name <- "Route_" + id_str;
            } else {
                name <- "Route_sans_nom";
            }
        }

        // ────────────────────────────────────────────────────────
        // 🎯 CLASSIFICATION EXHAUSTIVE (LOGIQUE CLEAN_OSM)
        // ────────────────────────────────────────────────────────
        
        // 🚌 BUS
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
        }
        // 🚋 TRAM
        else if (
            (railway = "tram") or (route = "tram") or (route_master = "tram")
        ) {
            route_type <- "tram";
            routeType_num <- 0;
            route_color <- #orange;
            route_width <- 2.0;
            nb_tram_routes <- nb_tram_routes + 1;
        }
        // 🚇 MÉTRO
        else if (
            (railway = "subway") or (railway = "metro") or
            (route = "subway") or (route = "metro") or (route_master = "subway")
        ) {
            route_type <- "metro";
            routeType_num <- 1;
            route_color <- #red;
            route_width <- 2.0;
            nb_metro_routes <- nb_metro_routes + 1;
        }
        // 🚂 TRAIN
        else if (
            railway != nil and railway != "" and
            !(railway in ["abandoned", "platform", "disused", "construction", "proposed", "razed", "dismantled"])
        ) {
            route_type <- "train";
            routeType_num <- 2;
            route_color <- #green;
            route_width <- 1.8;
            nb_train_routes <- nb_train_routes + 1;
        }
        // ❓ AUTRES
        else {
            route_type <- "other";
            routeType_num <- 99;
            route_color <- #lightgray;
            route_width <- 0.8;
            nb_other_routes <- nb_other_routes + 1;
        }

        // ────────────────────────────────────────────────────────
        // 📏 CALCUL PROPRIÉTÉS
        // ────────────────────────────────────────────────────────
        float length_meters <- geom.perimeter;
        int points_count <- length(geom.points);

        // ────────────────────────────────────────────────────────
        // ✅ CRÉATION AGENT AVEC ID CANONIQUE
        // ────────────────────────────────────────────────────────
        create network_route with: [
            shape::geom,
            route_type::route_type,
            routeType_num::routeType_num,
            route_color::route_color,
            route_width::route_width,
            name::name,
            
            // 🔑 IDENTITÉ OSM CANONIQUE
            osm_id::id_str,
            osm_type::osm_type,
            osm_uid::osm_uid,
            
            // 📋 Attributs OSM
            highway_type::highway,
            railway_type::railway,
            route_rel::route,
            bus_access::bus,
            ref_number::ref,
            
            // 📐 Propriétés
            length_m::length_meters,
            num_points::points_count
        ];
        
        nb_total_created <- nb_total_created + 1;
    }
    
    // ══════════════════════════════════════════════════════════
    // 📦 EXPORT COMPLET (LOGIQUE CLEAN_OSM)
    // ══════════════════════════════════════════════════════════
    action export_complete_network {
        write "\n=== 📦 EXPORT VERS SHAPEFILE ===";
        
        if empty(network_route) {
            write "❌ ERREUR : Aucun agent créé à exporter !";
            return;
        }
        
        string shapefile_path <- export_folder + "network_transport_complete.shp";
        
        // ✅ EXPORT AVEC TOUS LES ATTRIBUTS ID
        try {
            save network_route to: shapefile_path format: "shp" attributes: [
                "osm_uid"::osm_uid,          // 🔑 ID canonique (clé primaire)
                "osm_type"::osm_type,        // 🏷️ Type OSM
                "osm_id"::osm_id,            // 🔢 ID brut
                "name"::name,                // 📛 Nom
                "route_type"::route_type,    // 🚌 Type transport
                "routeType"::routeType_num,  // #️⃣ Code numérique
                "highway"::highway_type,     // 🛣️ Type highway
                "railway"::railway_type,     // 🚂 Type railway
                "ref"::ref_number,           // 🔖 Référence
                "length_m"::length_m         // 📏 Longueur
            ];
            
            write "✅ EXPORT COMPLET RÉUSSI : " + shapefile_path;
            write "📊 " + length(network_route) + " routes exportées avec ID canonique";
            
        } catch {
            write "❌ Erreur d'export complet - Tentative avec attributs minimaux...";
            
            try {
                save network_route to: shapefile_path format: "shp" attributes: [
                    "osm_uid"::osm_uid,
                    "osm_type"::osm_type,
                    "osm_id"::osm_id,
                    "name"::name,
                    "type"::route_type
                ];
                write "✅ EXPORT MINIMAL RÉUSSI : " + shapefile_path;
            } catch {
                write "❌ Échec attributs - Export géométrie seule...";
                save network_route to: shapefile_path format: "shp";
                write "✅ EXPORT GÉOMÉTRIE SEULE : " + shapefile_path;
            }
        }
    }
    
    // ══════════════════════════════════════════════════════════
    // 📦 EXPORT PAR TYPE (LOGIQUE CLEAN_OSM)
    // ══════════════════════════════════════════════════════════
    action export_by_type_fixed {
        write "\n=== 📦 EXPORT PAR TYPE DE TRANSPORT ===";
        
        // ────────────────────────────────────────────────────────
        // 🚌 EXPORT BUS
        // ────────────────────────────────────────────────────────
        list<network_route> bus_routes <- network_route where (each.route_type = "bus");
        write "🔍 Bus routes trouvées : " + length(bus_routes);
        
        if !empty(bus_routes) {
            string bus_path <- export_folder + "bus_routes.shp";
            
            try {
                save bus_routes to: bus_path format: "shp" attributes: [
                    "osm_uid"::osm_uid,
                    "osm_type"::osm_type,
                    "osm_id"::osm_id,
                    "name"::name,
                    "route_type"::route_type,
                    "highway"::highway_type,
                    "ref"::ref_number,
                    "length_m"::length_m
                ];
                write "✅ Bus exporté : " + length(bus_routes) + " routes → bus_routes.shp";
            } catch {
                write "❌ Erreur export bus - tentative export minimal";
                try {
                    save bus_routes to: bus_path format: "shp" attributes: [
                        "osm_uid"::osm_uid,
                        "name"::name,
                        "type"::route_type
                    ];
                    write "✅ Bus exporté (minimal) : " + length(bus_routes) + " routes";
                } catch {
                    write "❌ Erreur totale export bus";
                }
            }
        }
        
        // ────────────────────────────────────────────────────────
        // 🚋🚇🚂 EXPORT TRANSPORT PUBLIC
        // ────────────────────────────────────────────────────────
        list<network_route> public_transport <- network_route where (each.route_type in ["tram", "metro", "train"]);
        
        if !empty(public_transport) {
            write "🔍 Transport public trouvé : " + length(public_transport);
            string pt_path <- export_folder + "public_transport.shp";
            
            try {
                save public_transport to: pt_path format: "shp" attributes: [
                    "osm_uid"::osm_uid,
                    "osm_type"::osm_type,
                    "osm_id"::osm_id,
                    "name"::name,
                    "route_type"::route_type,
                    "railway"::railway_type,
                    "ref"::ref_number,
                    "length_m"::length_m
                ];
                write "✅ Transport public exporté : " + length(public_transport) + " → public_transport.shp";
            } catch {
                write "❌ Erreur export transport public - tentative export minimal";
                try {
                    save public_transport to: pt_path format: "shp" attributes: [
                        "osm_uid"::osm_uid,
                        "name"::name,
                        "type"::route_type
                    ];
                    write "✅ Transport public (minimal) exporté";
                } catch {
                    write "❌ Erreur totale export transport public";
                }
            }
        }
        
        write "🎯 EXPORT PAR TYPE TERMINÉ !";
    }
}

// ══════════════════════════════════════════════════════════
// 🚌 AGENT ROUTE (AVEC ID CANONIQUE OSM)
// ══════════════════════════════════════════════════════════
species network_route {
    // Visualisation
    geometry shape;
    string route_type;
    int routeType_num;
    rgb route_color;
    float route_width;
    string name;
    
    // 🔑 IDENTITÉ OSM CANONIQUE (comme Clean_OSM)
    string osm_id;     // ID brut
    string osm_type;   // Type OSM
    string osm_uid;    // 🌟 ID CANONIQUE : "way:123456"
    
    // Attributs OSM
    string highway_type;
    string railway_type;
    string route_rel;
    string bus_access;
    string ref_number;
    
    // Propriétés
    float length_m;
    int num_points;
    
    // ────────────────────────────────────────────────────────
    // 🎨 ASPECTS D'AFFICHAGE
    // ────────────────────────────────────────────────────────
    aspect default {
        if shape != nil {
            draw shape color: route_color width: route_width;
        }
    }
    
    aspect bus_focus {
        if shape != nil {
            if route_type = "bus" {
                draw shape color: #blue width: 4.0;
            } else {
                draw shape color: #lightgray width: 0.5;
            }
        }
    }
    
    aspect colored_by_type {
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
            } else {
                display_color <- #lightgray;
            }
            draw shape color: display_color width: 2.5;
        }
    }
}

// ══════════════════════════════════════════════════════════
// 🎯 EXPÉRIMENT : VUE GÉNÉRALE
// ══════════════════════════════════════════════════════════
experiment general_view type: gui {
    output {
        display "Toutes les routes" background: #white {
            species network_route aspect: default;
            
            overlay position: {10, 10} size: {300 #px, 280 #px} 
                    background: #white transparency: 0.9 border: #black {
                draw "🚌 ROUTES OSM" at: {15#px, 25#px} 
                     color: #black font: font("Arial", 14, #bold);
                
                draw "━━━━━━━━━━━━━━━━━━" at: {15#px, 45#px} color: #darkgray size: 10;
                
                draw "📊 STATISTIQUES" at: {20#px, 65#px} 
                     color: #darkblue font: font("Arial", 11, #bold);
                draw "Total routes : " + nb_total_created at: {25#px, 85#px} color: #black;
                
                draw "━━━━━━━━━━━━━━━━━━" at: {15#px, 105#px} color: #darkgray size: 10;
                
                draw "🚌 Bus : " + nb_bus_routes at: {25#px, 125#px} 
                     color: #blue font: font("Arial", 10, #bold);
                draw "🚋 Tram : " + nb_tram_routes at: {25#px, 145#px} color: #orange;
                draw "🚇 Métro : " + nb_metro_routes at: {25#px, 165#px} color: #red;
                draw "🚂 Train : " + nb_train_routes at: {25#px, 185#px} color: #green;
                draw "❓ Autres : " + nb_other_routes at: {25#px, 205#px} color: #gray;
                
                draw "━━━━━━━━━━━━━━━━━━" at: {15#px, 225#px} color: #darkgray size: 10;
                
                draw "🔑 ID OSM" at: {20#px, 245#px} 
                     color: #darkgreen font: font("Arial", 11, #bold);
                draw "Avec ID : " + (nb_total_created - nb_without_osm_id) 
                     at: {25#px, 265#px} color: #darkgreen;
            }
        }
        
        monitor "Routes totales" value: nb_total_created;
        monitor "Routes bus" value: nb_bus_routes;
    }
}

// ══════════════════════════════════════════════════════════
// 🎯 EXPÉRIMENT : FOCUS BUS
// ══════════════════════════════════════════════════════════
experiment bus_focus type: gui {
    output {
        display "Focus Routes Bus" background: #white {
            species network_route aspect: bus_focus;
            
            overlay position: {10, 10} size: {280 #px, 180 #px} 
                    background: #white transparency: 0.9 border: #black {
                draw "🚌 FOCUS BUS" at: {15#px, 25#px} 
                     color: #darkblue font: font("Arial", 14, #bold);
                
                draw "━━━━━━━━━━━━━━━━━" at: {15#px, 45#px} color: #darkgray size: 10;
                
                draw "Routes bus : " + nb_bus_routes at: {20#px, 70#px} 
                     color: #blue font: font("Arial", 12, #bold);
                draw "Autres routes : " + (nb_total_created - nb_bus_routes) 
                     at: {20#px, 95#px} color: #gray;
                
                draw "━━━━━━━━━━━━━━━━━" at: {15#px, 120#px} color: #darkgray size: 10;
                
                draw "Légende :" at: {20#px, 140#px} 
                     color: #black font: font("Arial", 10, #bold);
                draw "▬ Bleu épais = Bus" at: {25#px, 160#px} color: #blue;
            }
        }
        
        monitor "Routes bus" value: nb_bus_routes;
        monitor "% Bus" value: nb_total_created > 0 ? 
            ((nb_bus_routes * 100.0 / nb_total_created) with_precision 1) : 0.0;
    }
}