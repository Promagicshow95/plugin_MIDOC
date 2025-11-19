/**
 * Name: OSM_Bus_Visualizer
 * Description: Visualisation des routes de bus depuis API OSM (sans export)
 * Tags: OSM, bus, visualization, transport
 * Date: 2025-11-18
 */

model OSM_Bus_Visualizer

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
        "highway"::[],     // Routes (incluant busway)
        "railway"::[],     // Voies ferrées (tram, metro, train)
        "route"::[],       // Relations route (bus, tram, etc.)
        "bus"::[],         // Routes bus spécifiques
        "psv"::[]          // Public service vehicles
    ];
    
    // --- VARIABLES STATISTIQUES ---
    int nb_bus_routes <- 0;
    int nb_tram_routes <- 0;
    int nb_metro_routes <- 0;
    int nb_train_routes <- 0;
    int nb_other_routes <- 0;
    int nb_total_created <- 0;
    int nb_without_osm_id <- 0;

    init {
        write "=== 🚌 VISUALISATION ROUTES BUS OSM ===\n";
        
        // Chargement OSM depuis API
        file<geometry> osm_geometries <- osm_file<geometry>(adress, osm_data_to_generate);
        write "✅ Géométries OSM chargées : " + length(osm_geometries);
        
        // Créer les routes
        int valid_geoms <- 0;
        int invalid_geoms <- 0;
        
        loop geom over: osm_geometries {
            if geom != nil and length(geom.points) > 1 {
                do create_route_from_osm(geom);
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
        
        // Afficher un échantillon de routes bus
        if nb_bus_routes > 0 {
            write "\n=== 🔍 ÉCHANTILLON ROUTES BUS ===";
            list<network_route> bus_sample <- network_route where (each.route_type = "bus");
            int count <- 0;
            loop bus_route over: bus_sample {
                if count < 5 {
                    write "📍 Bus route : " + bus_route.name;
                    write "   └─ OSM UID : " + bus_route.osm_uid;
                    write "   └─ Longueur : " + (bus_route.length_m with_precision 0) + " m";
                    count <- count + 1;
                }
            }
        }
    }
    
    // ══════════════════════════════════════════════════════════
    // 🎯 CRÉATION ROUTE DEPUIS OSM - AVEC IDENTIFICATION
    // ══════════════════════════════════════════════════════════
    action create_route_from_osm(geometry geom) {
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
        // 🔑 RÉCUPÉRATION ID OSM
        // ────────────────────────────────────────────────────────
        string id_str <- (geom.attributes["@id"] as string);
        if (id_str = nil or id_str = "") { 
            id_str <- (geom.attributes["id"] as string); 
        }
        if (id_str = nil or id_str = "") { 
            id_str <- (geom.attributes["osm_id"] as string); 
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
        // 🔑 CONSTRUCTION ID CANONIQUE
        // ────────────────────────────────────────────────────────
        string osm_uid <- "";
        if (id_str != nil and id_str != "") {
            osm_uid <- osm_type + ":" + id_str;
        } else {
            nb_without_osm_id <- nb_without_osm_id + 1;
            osm_uid <- "";
        }
        
        // ────────────────────────────────────────────────────────
        // 📛 NOM PAR DÉFAUT
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
        // 🎯 CLASSIFICATION PAR TYPE DE TRANSPORT
        // ────────────────────────────────────────────────────────
        
        // 🚌 BUS (PRIORITÉ)
        if (
            (route = "bus") or (route = "trolleybus") or
            (route_master = "bus") or (highway = "busway") or
            (bus in ["yes", "designated"]) or (psv = "yes")
        ) {
            route_type <- "bus";
            routeType_num <- 3;
            route_color <- #blue;
            route_width <- 3.0;  // Plus épais pour les bus
            nb_bus_routes <- nb_bus_routes + 1;
        }
        // 🚋 TRAM
        else if (
            (railway = "tram") or (route = "tram") or (route_master = "tram")
        ) {
            route_type <- "tram";
            routeType_num <- 0;
            route_color <- #orange;
            route_width <- 2.5;
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
            route_width <- 2.5;
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
            route_width <- 2.0;
            nb_train_routes <- nb_train_routes + 1;
        }
        // ❓ AUTRES
        else {
            route_type <- "other";
            routeType_num <- 99;
            route_color <- #lightgray;
            route_width <- 1.0;
            nb_other_routes <- nb_other_routes + 1;
        }

        // ────────────────────────────────────────────────────────
        // 📏 CALCUL PROPRIÉTÉS
        // ────────────────────────────────────────────────────────
        float length_meters <- geom.perimeter;
        int points_count <- length(geom.points);

        // ────────────────────────────────────────────────────────
        // ✅ CRÉATION AGENT
        // ────────────────────────────────────────────────────────
        create network_route with: [
            shape::geom,
            route_type::route_type,
            routeType_num::routeType_num,
            route_color::route_color,
            route_width::route_width,
            name::name,
            
            // 🔑 Identité OSM
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
}

// ══════════════════════════════════════════════════════════
// 🚌 AGENT ROUTE
// ══════════════════════════════════════════════════════════
species network_route {
    // Visualisation
    geometry shape;
    string route_type;
    int routeType_num;
    rgb route_color;
    float route_width;
    string name;
    
    // Identité OSM
    string osm_id;
    string osm_type;
    string osm_uid;
    
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
            // Mettre en évidence les bus en bleu épais
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
    
    aspect with_label {
        if shape != nil {
            draw shape color: route_color width: route_width;
            if route_type = "bus" and name != nil {
                draw name color: #darkblue size: 10 at: location + {0, 50};
            }
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
        monitor "Routes tram" value: nb_tram_routes;
        monitor "Routes métro" value: nb_metro_routes;
        monitor "Routes train" value: nb_train_routes;
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

// ══════════════════════════════════════════════════════════
// 🎯 EXPÉRIMENT : COULEURS PAR TYPE
// ══════════════════════════════════════════════════════════
experiment colored_view type: gui {
    output {
        display "Vue Colorée par Type" background: #white {
            species network_route aspect: colored_by_type;
            
            overlay position: {10, 10} size: {250 #px, 220 #px} 
                    background: #white transparency: 0.9 border: #black {
                draw "🎨 LÉGENDE" at: {15#px, 25#px} 
                     color: #black font: font("Arial", 13, #bold);
                
                draw "━━━━━━━━━━━━━━━" at: {15#px, 45#px} color: #darkgray size: 9;
                
                draw "🚌 Bleu = Bus (" + nb_bus_routes + ")" 
                     at: {20#px, 65#px} color: #blue font: font("Arial", 11);
                draw "🚋 Orange = Tram (" + nb_tram_routes + ")" 
                     at: {20#px, 90#px} color: #orange font: font("Arial", 11);
                draw "🚇 Rouge = Métro (" + nb_metro_routes + ")" 
                     at: {20#px, 115#px} color: #red font: font("Arial", 11);
                draw "🚂 Vert = Train (" + nb_train_routes + ")" 
                     at: {20#px, 140#px} color: #green font: font("Arial", 11);
                draw "❓ Gris = Autres (" + nb_other_routes + ")" 
                     at: {20#px, 165#px} color: #gray font: font("Arial", 11);
                
                draw "━━━━━━━━━━━━━━━" at: {15#px, 190#px} color: #darkgray size: 9;
            }
        }
    }
}

// ══════════════════════════════════════════════════════════
// 🎯 EXPÉRIMENT : AVEC NOMS DES BUS
// ══════════════════════════════════════════════════════════
experiment bus_with_names type: gui {
    output {
        display "Routes Bus avec Noms" background: #white {
            species network_route aspect: with_label;
            
            overlay position: {10, 10} size: {280 #px, 140 #px} 
                    background: #white transparency: 0.9 border: #black {
                draw "🚌 BUS AVEC NOMS" at: {15#px, 25#px} 
                     color: #darkblue font: font("Arial", 13, #bold);
                
                draw "━━━━━━━━━━━━━━━━━" at: {15#px, 45#px} color: #darkgray size: 9;
                
                draw "Routes bus : " + nb_bus_routes at: {20#px, 70#px} 
                     color: #blue font: font("Arial", 11);
                draw "Noms affichés pour les bus" at: {20#px, 95#px} 
                     color: #darkblue font: font("Arial", 9);
                
                draw "━━━━━━━━━━━━━━━━━" at: {15#px, 115#px} color: #darkgray size: 9;
            }
        }
        
        monitor "Routes bus nommées" value: length(network_route where (each.route_type = "bus" and each.name != nil));
    }
}