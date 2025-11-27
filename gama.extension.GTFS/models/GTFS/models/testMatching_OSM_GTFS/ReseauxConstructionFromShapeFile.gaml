/**
 * Name: ReseauxConstructionFromShapeFile
 * Description: Reconstruction du réseau complet depuis shapefiles exportés
 * Tags: OSM, bus, shapefile, reconstruction, transport
 * Date: 2025-11-26
 */

model ReseauxConstructionFromShapeFile

global {
    // ══════════════════════════════════════════════════════════
    // 📁 FICHIERS
    // ══════════════════════════════════════════════════════════

    // Dossier contenant les shapefiles exportés
    string data_folder <- "../../results1/";

    // Enveloppe géométrique
    file boundary <- shape_file("../../includes/ShapeFileNantes.shp");
    geometry shape <- envelope(boundary);

    // Fichiers réseau complet exportés par type géométrique
    string lines_file <- data_folder + "network_lines_complete.shp";
    string points_file <- data_folder + "network_points_complete.shp";
    string polygons_file <- data_folder + "network_polygons_complete.shp";

    // 🆕 Fichier GTFS pour les arrêts
    string gtfs_folder <- "../../includes/nantes_gtfs";
    gtfs_file gtfs_f <- gtfs_file(gtfs_folder);

    // Graphe routier
    graph road_network;

    // ══════════════════════════════════════════════════════════
    // 📊 VARIABLES STATISTIQUES
    // ══════════════════════════════════════════════════════════

    int nb_bus_routes <- 0;
    int nb_tram_routes <- 0;
    int nb_metro_routes <- 0;
    int nb_train_routes <- 0;
    int nb_other_routes <- 0;
    int nb_total_loaded <- 0;
    int nb_lines_loaded <- 0;
    int nb_points_loaded <- 0;
    int nb_polygons_loaded <- 0;
    
    // 🆕 Statistique arrêts
    int nb_bus_stops <- 0;

    init {
        write "═══════════════════════════════════════════════════════════";
        write "🚌 RECONSTRUCTION RÉSEAU DEPUIS SHAPEFILES";
        write "═══════════════════════════════════════════════════════════\n";

        // ══════════════════════════════════════════════════════════
        // 📥 CHARGEMENT DES SHAPEFILES
        // ══════════════════════════════════════════════════════════

        // Charger les LineStrings (routes principales)
        if file_exists(lines_file) {
            write "📂 Chargement : network_lines_complete.shp";
            file lines_shapefile <- shape_file(lines_file);

            create network_route from: lines_shapefile with: [
                osm_uid::read("osm_uid"),
                osm_type::read("osm_type"),
                osm_id::read("osm_id"),
                name::read("name"),
                route_type::read("route_type"),
                routeType_num::int(read("routeType")),
                highway_type::read("highway"),
                railway_type::read("railway"),
                route_rel::read("route_rel"),
                bus_access::read("bus"),
                psv_access::read("psv"),
                ref_number::read("ref"),
                length_m::float(read("length_m"))
            ] {
                do assign_visual_properties;
            }

            nb_lines_loaded <- length(network_route);
            write "   ✅ " + nb_lines_loaded + " routes (LineStrings) chargées";
        } else {
            write "   ⚠️ Fichier non trouvé : network_lines_complete.shp";
        }

        // Charger les Points (si présents)
        if file_exists(points_file) {
            write "📂 Chargement : network_points_complete.shp";
            file points_shapefile <- shape_file(points_file);
            int count_before <- length(network_route);

            create network_route from: points_shapefile with: [
                osm_uid::read("osm_uid"),
                osm_type::read("osm_type"),
                osm_id::read("osm_id"),
                name::read("name"),
                route_type::read("route_type")
            ] {
                do assign_visual_properties;
            }

            nb_points_loaded <- length(network_route) - count_before;
            write "   ✅ " + nb_points_loaded + " points chargés";
        } else {
            write "   ℹ️ Pas de fichier points (normal pour un réseau de routes)";
        }

        // Charger les Polygones (si présents)
        if file_exists(polygons_file) {
            write "📂 Chargement : network_polygons_complete.shp";
            file polygons_shapefile <- shape_file(polygons_file);
            int count_before <- length(network_route);

            create network_route from: polygons_shapefile with: [
                osm_uid::read("osm_uid"),
                osm_type::read("osm_type"),
                osm_id::read("osm_id"),
                name::read("name"),
                route_type::read("route_type")
            ] {
                do assign_visual_properties;
            }

            nb_polygons_loaded <- length(network_route) - count_before;
            write "   ✅ " + nb_polygons_loaded + " polygones chargés";
        } else {
            write "   ℹ️ Pas de fichier polygones";
        }

        nb_total_loaded <- length(network_route);

        // ══════════════════════════════════════════════════════════
        // 🆕 CHARGEMENT DES ARRÊTS GTFS
        // ══════════════════════════════════════════════════════════
        write "\n━━━ 🚏 CHARGEMENT ARRÊTS GTFS ━━━";
        
        try {
            create bus_stop from: gtfs_f;
            
            // Filtrer uniquement les arrêts de bus (routeType = 3)
            list<bus_stop> non_bus_stops <- bus_stop where (each.routeType != 3);
            ask non_bus_stops {
                do die;
            }
            
            nb_bus_stops <- length(bus_stop);
            write "✅ Arrêts bus chargés : " + nb_bus_stops;
            
        } catch {
            write "❌ Erreur chargement GTFS : " + gtfs_folder;
            nb_bus_stops <- 0;
        }

        // ══════════════════════════════════════════════════════════
        // 🛤️ CRÉATION DU GRAPHE ROUTIER
        // ══════════════════════════════════════════════════════════
        if (length(network_route) > 0) {
            list<geometry> route_geoms <- network_route collect each.shape;
            route_geoms <- route_geoms where (each != nil);
            
            if !empty(route_geoms) {
                road_network <- as_edge_graph(route_geoms);
                write "\n✅ Graphe créé avec " + length(road_network.edges) + " arêtes";
            }
        }

        // ══════════════════════════════════════════════════════════
        // 📊 STATISTIQUES PAR TYPE
        // ══════════════════════════════════════════════════════════

        nb_bus_routes <- length(network_route where (each.route_type = "bus"));
        nb_tram_routes <- length(network_route where (each.route_type = "tram"));
        nb_metro_routes <- length(network_route where (each.route_type = "metro"));
        nb_train_routes <- length(network_route where (each.route_type = "train"));
        nb_other_routes <- length(network_route where !(each.route_type in ["bus","tram","metro","train"]));

        write "\n═══════════════════════════════════════════════════════════";
        write "📊 RÉSULTATS CHARGEMENT";
        write "═══════════════════════════════════════════════════════════";
        write "📏 LineStrings : " + nb_lines_loaded;
        write "📍 Points      : " + nb_points_loaded;
        write "🔷 Polygons    : " + nb_polygons_loaded;
        write "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━";
        write "🛤️ TOTAL ROUTES : " + nb_total_loaded;
        write "🚏 ARRÊTS BUS   : " + nb_bus_stops;

        write "\n═══════════════════════════════════════════════════════════";
        write "📈 RÉPARTITION PAR TYPE DE TRANSPORT";
        write "═══════════════════════════════════════════════════════════";
        write "🚌 Bus   : " + nb_bus_routes;
        write "🚋 Tram  : " + nb_tram_routes;
        write "🚇 Métro : " + nb_metro_routes;
        write "🚂 Train : " + nb_train_routes;
        write "❓ Autres: " + nb_other_routes;

        write "\n✅ CHARGEMENT TERMINÉ - Réseau prêt pour visualisation\n";
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

    // Identité OSM canonique
    string osm_id;
    string osm_type;
    string osm_uid;

    // Attributs OSM
    string highway_type;
    string railway_type;
    string route_rel;
    string bus_access;
    string psv_access;
    string ref_number;

    // Propriétés
    float length_m;
    int num_points;

    // ══════════════════════════════════════════════════════════
    // 🎨 ASSIGNATION DES PROPRIÉTÉS VISUELLES
    // ══════════════════════════════════════════════════════════
    action assign_visual_properties {
        if route_type = "bus" {
            route_color <- #blue;
            route_width <- 2.5;
        } else if route_type = "tram" {
            route_color <- #orange;
            route_width <- 2.0;
        } else if route_type = "metro" {
            route_color <- #red;
            route_width <- 2.0;
        } else if route_type = "train" {
            route_color <- #green;
            route_width <- 1.8;
        } else {
            route_color <- #lightgray;
            route_width <- 0.8;
        }

        if shape != nil {
            num_points <- length(shape.points);
            if length_m = 0.0 or length_m = nil {
                length_m <- shape.perimeter;
            }
        }
    }

    // ══════════════════════════════════════════════════════════
    // 🎨 ASPECTS D'AFFICHAGE
    // ══════════════════════════════════════════════════════════

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
// 🚏 AGENT ARRÊT DE BUS (GTFS)
// ══════════════════════════════════════════════════════════
species bus_stop skills: [TransportStopSkill] {
    aspect base {
        if (routeType = 3) {
            draw circle(50) color: #red border: #darkred;
        }
    }
    
    aspect with_name {
        if (routeType = 3) {
            draw circle(50) color: #red border: #darkred;
            draw stopName color: #black size: 8 at: location + {0, 60};
        }
    }
}

// ══════════════════════════════════════════════════════════
// 🎯 EXPÉRIMENT : VUE GÉNÉRALE
// ══════════════════════════════════════════════════════════
experiment general_view type: gui {
    output {
        display "Réseau complet depuis shapefiles" background: #white {
            species network_route aspect: default;
            species bus_stop aspect: base;

            overlay position: {10, 10} size: {320 #px, 340 #px}
                    background: #white transparency: 0.9 border: #black {
                draw "🚌 RÉSEAU DEPUIS SHAPEFILES" at: {15#px, 25#px}
                     color: #black font: font("Arial", 14, #bold);

                draw "━━━━━━━━━━━━━━━━━━━━━━" at: {15#px, 45#px} color: #darkgray size: 10;

                draw "📊 CHARGEMENT" at: {20#px, 65#px}
                     color: #darkblue font: font("Arial", 11, #bold);
                draw "Total routes : " + nb_total_loaded at: {25#px, 85#px} color: #black;
                draw "  Lines   : " + nb_lines_loaded at: {25#px, 100#px} color: #darkgreen;
                draw "  Points  : " + nb_points_loaded at: {25#px, 115#px} color: #darkgreen;
                draw "  Polygons: " + nb_polygons_loaded at: {25#px, 130#px} color: #darkgreen;
                draw "🚏 Arrêts bus : " + nb_bus_stops at: {25#px, 150#px} color: #red;

                draw "━━━━━━━━━━━━━━━━━━━━━━" at: {15#px, 170#px} color: #darkgray size: 10;

                draw "🚦 PAR TYPE" at: {20#px, 190#px}
                     color: #darkblue font: font("Arial", 11, #bold);
                draw "🚌 Bus   : " + nb_bus_routes at: {25#px, 210#px}
                     color: #blue font: font("Arial", 10, #bold);
                draw "🚋 Tram  : " + nb_tram_routes at: {25#px, 230#px} color: #orange;
                draw "🚇 Métro : " + nb_metro_routes at: {25#px, 250#px} color: #red;
                draw "🚂 Train : " + nb_train_routes at: {25#px, 270#px} color: #green;
                draw "❓ Autres: " + nb_other_routes at: {25#px, 290#px} color: #gray;
                
                draw "━━━━━━━━━━━━━━━━━━━━━━" at: {15#px, 310#px} color: #darkgray size: 10;
                draw "✅ Réseau prêt" at: {20#px, 330#px} color: #darkgreen;
            }
        }

        monitor "Routes totales" value: nb_total_loaded;
        monitor "Routes bus" value: nb_bus_routes;
        monitor "Arrêts bus" value: nb_bus_stops;
    }
}

// ══════════════════════════════════════════════════════════
// 🎯 EXPÉRIMENT : FOCUS BUS
// ══════════════════════════════════════════════════════════
experiment bus_focus type: gui {
    output {
        display "Focus Routes Bus (depuis shapefiles)" background: #white {
            species network_route aspect: bus_focus;
            species bus_stop aspect: base;

            overlay position: {10, 10} size: {300 #px, 220 #px}
                    background: #white transparency: 0.9 border: #black {
                draw "🚌 FOCUS BUS" at: {15#px, 25#px}
                     color: #darkblue font: font("Arial", 14, #bold);

                draw "━━━━━━━━━━━━━━━━━━" at: {15#px, 45#px} color: #darkgray size: 10;

                draw "Routes bus : " + nb_bus_routes at: {20#px, 70#px}
                     color: #blue font: font("Arial", 12, #bold);
                draw "Arrêts bus : " + nb_bus_stops at: {20#px, 95#px}
                     color: #red font: font("Arial", 12, #bold);
                draw "Autres routes : " + (nb_total_loaded - nb_bus_routes)
                     at: {20#px, 120#px} color: #gray;

                draw "━━━━━━━━━━━━━━━━━━" at: {15#px, 145#px} color: #darkgray size: 10;

                draw "Légende :" at: {20#px, 165#px}
                     color: #black font: font("Arial", 10, #bold);
                draw "▬ Bleu = Routes Bus" at: {25#px, 185#px} color: #blue;
                draw "● Rouge = Arrêts" at: {25#px, 205#px} color: #red;
            }
        }

        monitor "Routes bus" value: nb_bus_routes;
        monitor "Arrêts bus" value: nb_bus_stops;
    }
}

// ══════════════════════════════════════════════════════════
// 🎯 EXPÉRIMENT : VUE PAR TYPE
// ══════════════════════════════════════════════════════════
experiment colored_by_type type: gui {
    output {
        display "Routes colorées par type" background: #white {
            species network_route aspect: colored_by_type;
            species bus_stop aspect: base;

            overlay position: {10, 10} size: {280 #px, 250 #px}
                    background: #white transparency: 0.9 border: #black {
                draw "🎨 PAR TYPE DE TRANSPORT" at: {15#px, 25#px}
                     color: #black font: font("Arial", 13, #bold);

                draw "━━━━━━━━━━━━━━━━━━" at: {15#px, 45#px} color: #darkgray size: 10;

                draw "Légende :" at: {20#px, 65#px}
                     color: #black font: font("Arial", 11, #bold);

                draw "▬ Bleu = Bus (" + nb_bus_routes + ")"
                     at: {25#px, 90#px} color: #blue font: font("Arial", 10);
                draw "▬ Orange = Tram (" + nb_tram_routes + ")"
                     at: {25#px, 115#px} color: #orange font: font("Arial", 10);
                draw "▬ Rouge = Métro (" + nb_metro_routes + ")"
                     at: {25#px, 140#px} color: #red font: font("Arial", 10);
                draw "▬ Vert = Train (" + nb_train_routes + ")"
                     at: {25#px, 165#px} color: #green font: font("Arial", 10);
                draw "▬ Gris = Autres (" + nb_other_routes + ")"
                     at: {25#px, 190#px} color: #gray font: font("Arial", 10);
                     
                draw "━━━━━━━━━━━━━━━━━━" at: {15#px, 210#px} color: #darkgray size: 10;
                draw "● Arrêts bus : " + nb_bus_stops at: {25#px, 235#px} color: #red;
            }
        }

        monitor "Total routes" value: nb_total_loaded;
        monitor "Arrêts bus" value: nb_bus_stops;
    }
}
