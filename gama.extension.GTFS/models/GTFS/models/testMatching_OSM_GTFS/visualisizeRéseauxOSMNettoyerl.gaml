/**
 * Reconstruction du réseau complet depuis shapefiles OSM exportés
 * 
 * Charge tous les shapefiles exportés par Clean_OSM_To_Shapefile et
 * reconstruit le réseau complet avec tous les attributs OSM
 */

model Rebuild_Network_From_Shapefiles

global {
    // ============================================================
    // === CONFIGURATION ===
    // ============================================================
    string import_folder <- "../../results1/";
    shape_file boundary_shp <- shape_file("../../includes/ShapeFileNantes.shp");
    geometry shape <- envelope(boundary_shp);
    
    // ============================================================
    // === STATISTIQUES ===
    // ============================================================
    int nb_bus_routes <- 0;
    int nb_tram_routes <- 0;
    int nb_metro_routes <- 0;
    int nb_train_routes <- 0;
    int nb_cycleway_routes <- 0;
    int nb_road_routes <- 0;
    int nb_other_routes <- 0;
    int nb_total_loaded <- 0;
    int nb_with_osm_id <- 0;
    
    // ============================================================
    // === RÉSEAU GLOBAL ===
    // ============================================================
    graph complete_network;
    graph bus_network;
    graph road_network;
    graph public_transport_network;
    
    // ============================================================
    // === INITIALISATION ===
    // ============================================================
    init {
        write "╔═══════════════════════════════════════════════════════╗";
        write "║   RECONSTRUCTION RÉSEAU DEPUIS SHAPEFILES           ║";
        write "╚═══════════════════════════════════════════════════════╝\n";
        
        // ÉTAPE 1: Charger routes de bus (par batch)
        do load_bus_routes;
        
        // ÉTAPE 2: Charger routes principales (par batch)
        do load_main_roads;
        
        // ÉTAPE 3: Charger transport public (tram, métro, train)
        do load_public_transport;
        
        // ÉTAPE 4: Charger pistes cyclables
        do load_cycleways;
        
        // ÉTAPE 5: Construire les graphes
        do build_networks;
        
        // ÉTAPE 6: Statistiques finales
        do print_summary;
    }
    
    // ============================================================
    // === CHARGEMENT ROUTES DE BUS (PAR BATCH)
    // ============================================================
    action load_bus_routes {
        write "🚌 Chargement routes de bus...";
        
        int batch_num <- 0;
        bool continue_loading <- true;
        int routes_loaded <- 0;
        
        loop while: continue_loading {
            string filepath <- import_folder + "bus_routes_part" + batch_num + ".shp";
            
            try {
                shape_file shp <- shape_file(filepath);
                
                // Créer les agents depuis le shapefile
                create network_route from: shp with: [
                    osm_uid:: string(get("osm_uid")),
                    osm_type:: string(get("osm_type")),
                    osm_id:: string(get("osm_id")),
                    name:: string(get("name")),
                    route_type:: string(get("route_type")),
                    routeType_num:: int(get("routeType")),
                    highway_type:: string(get("highway")),
                    railway_type:: string(get("railway")),
                    ref_number:: string(get("ref")),
                    length_m:: float(get("length_m"))
                ] {
                    // Définir la couleur selon le type
                    route_color <- #blue;
                    route_width <- 2.5;
                    
                    // Compter les routes avec ID
                    if (osm_uid != nil and osm_uid != "") {
                        nb_with_osm_id <- nb_with_osm_id + 1;
                    }
                }
                
                routes_loaded <- routes_loaded + length(shp.contents);
                write "  ✅ Batch " + batch_num + ": " + length(shp.contents) + " routes";
                batch_num <- batch_num + 1;
                
            } catch {
                if (batch_num = 0) {
                    write "  ⚠️  Aucun fichier bus_routes trouvé";
                }
                continue_loading <- false;
            }
        }
        
        nb_bus_routes <- routes_loaded;
        write "  📊 Total routes bus: " + nb_bus_routes;
    }
    
    // ============================================================
    // === CHARGEMENT ROUTES PRINCIPALES (PAR BATCH)
    // ============================================================
    action load_main_roads {
        write "\n🛣️  Chargement routes principales...";
        
        int batch_num <- 0;
        bool continue_loading <- true;
        int routes_loaded <- 0;
        
        loop while: continue_loading {
            string filepath <- import_folder + "main_roads_part" + batch_num + ".shp";
            
            try {
                shape_file shp <- shape_file(filepath);
                
                create network_route from: shp with: [
                    osm_uid:: string(get("osm_uid")),
                    osm_type:: string(get("osm_type")),
                    osm_id:: string(get("osm_id")),
                    name:: string(get("name")),
                    route_type:: string(get("route_type")),
                    routeType_num:: int(get("routeType")),
                    highway_type:: string(get("highway")),
                    railway_type:: string(get("railway")),
                    ref_number:: string(get("ref")),
                    length_m:: float(get("length_m"))
                ] {
                    route_color <- #gray;
                    route_width <- 1.0;
                    
                    if (osm_uid != nil and osm_uid != "") {
                        nb_with_osm_id <- nb_with_osm_id + 1;
                    }
                }
                
                routes_loaded <- routes_loaded + length(shp.contents);
                write "  ✅ Batch " + batch_num + ": " + length(shp.contents) + " routes";
                batch_num <- batch_num + 1;
                
            } catch {
                if (batch_num = 0) {
                    write "  ⚠️  Aucun fichier main_roads trouvé";
                }
                continue_loading <- false;
            }
        }
        
        nb_road_routes <- routes_loaded;
        write "  📊 Total routes principales: " + nb_road_routes;
    }
    
    // ============================================================
    // === CHARGEMENT TRANSPORT PUBLIC
    // ============================================================
    action load_public_transport {
        write "\n🚋 Chargement transport public...";
        
        string filepath <- import_folder + "public_transport.shp";
        
        try {
            shape_file shp <- shape_file(filepath);
            
            create network_route from: shp with: [
                osm_uid:: string(get("osm_uid")),
                osm_type:: string(get("osm_type")),
                osm_id:: string(get("osm_id")),
                name:: string(get("name")),
                route_type:: string(get("route_type")),
                routeType_num:: int(get("routeType")),
                highway_type:: string(get("highway")),
                railway_type:: string(get("railway")),
                ref_number:: string(get("ref")),
                length_m:: float(get("length_m"))
            ] {
                // Définir couleur selon le type
                if (route_type = "tram") {
                    route_color <- #orange;
                    route_width <- 2.0;
                    nb_tram_routes <- nb_tram_routes + 1;
                } else if (route_type = "metro") {
                    route_color <- #red;
                    route_width <- 2.0;
                    nb_metro_routes <- nb_metro_routes + 1;
                } else if (route_type = "train") {
                    route_color <- #green;
                    route_width <- 1.8;
                    nb_train_routes <- nb_train_routes + 1;
                }
                
                if (osm_uid != nil and osm_uid != "") {
                    nb_with_osm_id <- nb_with_osm_id + 1;
                }
            }
            
            write "  ✅ " + length(shp.contents) + " routes de transport public";
            write "    • Tram: " + nb_tram_routes;
            write "    • Métro: " + nb_metro_routes;
            write "    • Train: " + nb_train_routes;
            
        } catch {
            write "  ⚠️  Fichier public_transport.shp non trouvé";
        }
    }
    
    // ============================================================
    // === CHARGEMENT PISTES CYCLABLES
    // ============================================================
    action load_cycleways {
        write "\n🚴 Chargement pistes cyclables...";
        
        string filepath <- import_folder + "cycleways.shp";
        
        try {
            shape_file shp <- shape_file(filepath);
            
            create network_route from: shp with: [
                osm_uid:: string(get("osm_uid")),
                osm_type:: string(get("osm_type")),
                osm_id:: string(get("osm_id")),
                name:: string(get("name")),
                route_type:: "cycleway",
                routeType_num:: 10,
                highway_type:: string(get("highway")),
                ref_number:: string(get("ref")),
                length_m:: float(get("length_m"))
            ] {
                route_color <- #purple;
                route_width <- 1.2;
                
                if (osm_uid != nil and osm_uid != "") {
                    nb_with_osm_id <- nb_with_osm_id + 1;
                }
            }
            
            nb_cycleway_routes <- length(shp.contents);
            write "  ✅ " + nb_cycleway_routes + " pistes cyclables";
            
        } catch {
            write "  ⚠️  Fichier cycleways.shp non trouvé";
        }
    }
    
    // ============================================================
    // === CONSTRUCTION DES GRAPHES
    // ============================================================
    action build_networks {
        write "\n🔗 Construction des graphes de navigation...";
        
        // GRAPHE COMPLET (toutes les routes)
        if (length(network_route) > 0) {
            list<geometry> all_geoms <- network_route collect each.shape;
            complete_network <- as_edge_graph(all_geoms);
            write "  ✅ Graphe complet: " + length(complete_network.vertices) + " nœuds, " + 
                  length(complete_network.edges) + " arêtes";
        }
        
        // GRAPHE BUS
        list<network_route> bus_routes <- network_route where (each.route_type = "bus");
        if (length(bus_routes) > 0) {
            list<geometry> bus_geoms <- bus_routes collect each.shape;
            bus_network <- as_edge_graph(bus_geoms);
            write "  ✅ Graphe bus: " + length(bus_network.vertices) + " nœuds, " + 
                  length(bus_network.edges) + " arêtes";
        }
        
        // GRAPHE ROUTES PRINCIPALES
        list<network_route> road_routes <- network_route where (each.route_type = "road");
        if (length(road_routes) > 0) {
            list<geometry> road_geoms <- road_routes collect each.shape;
            road_network <- as_edge_graph(road_geoms);
            write "  ✅ Graphe routes: " + length(road_network.vertices) + " nœuds, " + 
                  length(road_network.edges) + " arêtes";
        }
        
        // GRAPHE TRANSPORT PUBLIC
        list<network_route> pt_routes <- network_route where (each.route_type in ["tram", "metro", "train"]);
        if (length(pt_routes) > 0) {
            list<geometry> pt_geoms <- pt_routes collect each.shape;
            public_transport_network <- as_edge_graph(pt_geoms);
            write "  ✅ Graphe transport public: " + length(public_transport_network.vertices) + " nœuds, " + 
                  length(public_transport_network.edges) + " arêtes";
        }
    }
    
    // ============================================================
    // === STATISTIQUES FINALES
    // ============================================================
    action print_summary {
        nb_total_loaded <- length(network_route);
        
        write "\n╔═══════════════════════════════════════════════════════╗";
        write "║             RÉSEAU RECONSTRUIT                       ║";
        write "╠═══════════════════════════════════════════════════════╣";
        write "║ 🚌 Routes Bus:       " + nb_bus_routes;
        write "║ 🚋 Routes Tram:      " + nb_tram_routes;
        write "║ 🚇 Routes Métro:     " + nb_metro_routes;
        write "║ 🚂 Routes Train:     " + nb_train_routes;
        write "║ 🚴 Routes Cycleway:  " + nb_cycleway_routes;
        write "║ 🛣️ Routes Principales:" + nb_road_routes;
        write "╠═══════════════════════════════════════════════════════╣";
        write "║ 📊 TOTAL:            " + nb_total_loaded;
        write "║ 🔑 Avec ID OSM:      " + nb_with_osm_id;
        write "╠═══════════════════════════════════════════════════════╣";
        write "║ 🔗 Graphe complet:   " + (complete_network != nil ? "✅" : "❌");
        write "║ 🔗 Graphe bus:       " + (bus_network != nil ? "✅" : "❌");
        write "║ 🔗 Graphe routes:    " + (road_network != nil ? "✅" : "❌");
        write "║ 🔗 Graphe TP:        " + (public_transport_network != nil ? "✅" : "❌");
        write "╚═══════════════════════════════════════════════════════╝";
        
        write "\n✅ Réseau complet reconstruit et prêt à utiliser !";
    }
}

// ============================================================
// === ESPÈCE ROUTE RÉSEAU
// ============================================================
species network_route {
    // Attributs géométriques
    geometry shape;
    
    // Identité OSM
    string osm_uid;     // ID canonique: "way:123456"
    string osm_type;    // Type OSM: "way" / "relation" / "node"
    string osm_id;      // ID brut: "123456"
    
    // Attributs transport
    string route_type;      // "bus", "tram", "metro", "train", etc.
    int routeType_num;      // Code numérique GTFS
    string name;            // Nom de la route
    string ref_number;      // Numéro de ligne
    
    // Attributs OSM
    string highway_type;    // Type highway OSM
    string railway_type;    // Type railway OSM
    
    // Propriétés calculées
    float length_m;         // Longueur en mètres
    
    // Visualisation
    rgb route_color;
    float route_width;
    
    // ========================================
    // ASPECTS D'AFFICHAGE
    // ========================================
    aspect default {
        if (shape != nil) {
            draw shape color: route_color width: route_width;
        }
    }
    
    aspect thin {
        if (shape != nil) {
            draw shape color: route_color width: 1.0;
        }
    }
    
    aspect thick {
        if (shape != nil) {
            draw shape color: route_color width: (route_width * 2);
        }
    }
    
    aspect with_name {
        if (shape != nil) {
            draw shape color: route_color width: route_width;
            if (name != nil and name != "") {
                draw name color: #black font: font("Arial", 8) at: location;
            }
        }
    }
}

// ============================================================
// === EXPÉRIENCE 1: VUE COMPLÈTE
// ============================================================
experiment Exp_Complete_Network type: gui {
    output {
        display "Réseau Complet" type: 2d background: #white {
            species network_route aspect: thin;
            
            overlay position: {10, 10} size: {250 #px, 240 #px} 
                    background: #white transparency: 0.1 border: #black {
                draw "RÉSEAU COMPLET" at: {10 #px, 20 #px} 
                     font: font("Arial", 13, #bold);
                draw "━━━━━━━━━━━━━━━━━━━━" at: {10 #px, 35 #px} color: #gray;
                
                draw "📊 Statistiques:" at: {15 #px, 55 #px} font: font("Arial", 10, #bold);
                draw "Total routes: " + length(network_route) at: {20 #px, 70 #px};
                draw "🚌 Bus: " + nb_bus_routes at: {20 #px, 85 #px} color: #blue;
                draw "🛣️ Routes: " + nb_road_routes at: {20 #px, 100 #px} color: #gray;
                draw "🚋 Tram: " + nb_tram_routes at: {20 #px, 115 #px} color: #orange;
                draw "🚇 Métro: " + nb_metro_routes at: {20 #px, 130 #px} color: #red;
                draw "🚂 Train: " + nb_train_routes at: {20 #px, 145 #px} color: #green;
                draw "🚴 Cycleway: " + nb_cycleway_routes at: {20 #px, 160 #px} color: #purple;
                
                draw "━━━━━━━━━━━━━━━━━━━━" at: {10 #px, 180 #px} color: #gray;
                draw "🔗 Graphes disponibles:" at: {15 #px, 195 #px} font: font("Arial", 9);
                draw "✅ Complet, Bus, Routes, TP" at: {20 #px, 210 #px} font: font("Arial", 8);
            }
        }
        
        monitor "Total routes" value: nb_total_loaded;
        monitor "Avec ID OSM" value: nb_with_osm_id color: #green;
        monitor "Nœuds graphe" value: complete_network != nil ? length(complete_network.vertices) : 0;
        monitor "Arêtes graphe" value: complete_network != nil ? length(complete_network.edges) : 0;
    }
}

// ============================================================
// === EXPÉRIENCE 2: ROUTES BUS UNIQUEMENT
// ============================================================
experiment Exp_Bus_Only type: gui {
    output {
        display "Routes Bus" type: 2d background: #white {
            species network_route aspect: default transparency: 0.0 {
                if (route_type = "bus") {
                    draw shape color: #blue width: 2.5;
                }
            }
            
            overlay position: {10, 10} size: {220 #px, 140 #px} 
                    background: #white transparency: 0.1 border: #black {
                draw "ROUTES BUS" at: {10 #px, 20 #px} 
                     font: font("Arial", 13, #bold) color: #blue;
                draw "━━━━━━━━━━━━━━━━━━" at: {10 #px, 35 #px} color: #gray;
                
                draw "🚌 Total: " + nb_bus_routes at: {15 #px, 55 #px} 
                     font: font("Arial", 11);
                
                if (bus_network != nil) {
                    draw "🔗 Graphe bus:" at: {15 #px, 75 #px} font: font("Arial", 10);
                    draw "  Nœuds: " + length(bus_network.vertices) at: {20 #px, 90 #px} 
                         font: font("Arial", 9);
                    draw "  Arêtes: " + length(bus_network.edges) at: {20 #px, 105 #px} 
                         font: font("Arial", 9);
                }
            }
        }
        
        monitor "Routes bus" value: nb_bus_routes color: #blue;
        monitor "Graphe bus disponible" value: bus_network != nil;
    }
}

// ============================================================
// === EXPÉRIENCE 3: TRANSPORT PUBLIC
// ============================================================
experiment Exp_Public_Transport type: gui {
    output {
        display "Transport Public" type: 2d background: #white {
            species network_route aspect: default transparency: 0.0 {
                if (route_type in ["tram", "metro", "train"]) {
                    draw shape color: route_color width: route_width;
                }
            }
            
            overlay position: {10, 10} size: {220 #px, 160 #px} 
                    background: #white transparency: 0.1 border: #black {
                draw "TRANSPORT PUBLIC" at: {10 #px, 20 #px} 
                     font: font("Arial", 12, #bold);
                draw "━━━━━━━━━━━━━━━━━━" at: {10 #px, 35 #px} color: #gray;
                
                draw "🚋 Tram: " + nb_tram_routes at: {15 #px, 55 #px} color: #orange;
                draw "🚇 Métro: " + nb_metro_routes at: {15 #px, 75 #px} color: #red;
                draw "🚂 Train: " + nb_train_routes at: {15 #px, 95 #px} color: #green;
                
                draw "━━━━━━━━━━━━━━━━━━" at: {10 #px, 115 #px} color: #gray;
                draw "Total: " + (nb_tram_routes + nb_metro_routes + nb_train_routes) 
                     at: {15 #px, 135 #px} font: font("Arial", 10, #bold);
            }
        }
        
        monitor "Tram" value: nb_tram_routes color: #orange;
        monitor "Métro" value: nb_metro_routes color: #red;
        monitor "Train" value: nb_train_routes color: #green;
    }
}

// ============================================================
// === EXPÉRIENCE 4: PAR TYPE (COLORÉ)
// ============================================================
experiment Exp_Colored_By_Type type: gui {
    output {
        display "Réseau par Type" type: 2d background: #white {
            species network_route aspect: default;
            
            overlay position: {10, 10} size: {220 #px, 200 #px} 
                    background: #white transparency: 0.1 border: #black {
                draw "LÉGENDE" at: {10 #px, 20 #px} 
                     font: font("Arial", 13, #bold);
                draw "━━━━━━━━━━━━━━━━━━" at: {10 #px, 35 #px} color: #gray;
                
                draw line([{15 #px, 55 #px}, {35 #px, 55 #px}]) color: #blue width: 3;
                draw "Bus" at: {45 #px, 56 #px};
                
                draw line([{15 #px, 75 #px}, {35 #px, 75 #px}]) color: #orange width: 3;
                draw "Tram" at: {45 #px, 76 #px};
                
                draw line([{15 #px, 95 #px}, {35 #px, 95 #px}]) color: #red width: 3;
                draw "Métro" at: {45 #px, 96 #px};
                
                draw line([{15 #px, 115 #px}, {35 #px, 115 #px}]) color: #green width: 3;
                draw "Train" at: {45 #px, 116 #px};
                
                draw line([{15 #px, 135 #px}, {35 #px, 135 #px}]) color: #purple width: 3;
                draw "Cycleway" at: {45 #px, 136 #px};
                
                draw line([{15 #px, 155 #px}, {35 #px, 155 #px}]) color: #gray width: 3;
                draw "Routes" at: {45 #px, 156 #px};
            }
        }
        
        monitor "Total" value: nb_total_loaded;
    }
}
