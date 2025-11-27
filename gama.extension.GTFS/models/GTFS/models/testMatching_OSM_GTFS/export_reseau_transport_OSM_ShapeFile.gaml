/**
 * Name: export_reseau_transport_OSM_ShapeFile
 * Author: Promagicshow95
 * Description: Export OSM vers shapefile - VERSION ID CANONIQUE UNIQUE (CORRIGÉE)
 * Tags: OSM, shapefile, export, network, transport
 */

model Clean_OSM_To_Shapefile

global {
    // --- FICHIERS ---
    file data_file <- shape_file("../../includes/shapeFileNantes.shp");
    geometry shape <- envelope(data_file);
    
    // 🆕 Fichier GTFS pour les arrêts
    string gtfs_folder <- "../../includes/nantes_gtfs";
    gtfs_file gtfs_f <- gtfs_file(gtfs_folder);
    
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
    int nb_without_osm_id <- 0;
    
    // 🆕 Statistique arrêts GTFS
    int nb_bus_stops <- 0;
    
    // --- PARAMÈTRES D'EXPORT ---
    string export_folder <- "../../results1/";

    init {
        write "=== EXPORT OSM AVEC ID CANONIQUE UNIQUE (CORRIGÉ) ===";
        write "🔑 Système d'identification : osm_type:osm_id";
        
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
        write "⚠️ Routes sans ID OSM : " + nb_without_osm_id;
        
        // 🆕 CHARGEMENT DES ARRÊTS GTFS
        write "\n=== 🚏 CHARGEMENT ARRÊTS GTFS ===";
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
        
        // 🆕 VALIDATION AVANT EXPORT
        do validate_export;
        
        // ✅ EXPORT IMMÉDIAT VERS SHAPEFILE
        do export_complete_network;
        
        // 🆕 EXPORT PAR TYPE POUR ÉVITER LES FICHIERS TROP VOLUMINEUX
        do export_by_type_fixed;
        
        // Statistiques finales
        write "\n=== 📊 STATISTIQUES RÉSEAU EXPORTÉ ===";
        write "🚌 Routes Bus : " + nb_bus_routes;
        write "🚋 Routes Tram : " + nb_tram_routes; 
        write "🚇 Routes Métro : " + nb_metro_routes;
        write "🚂 Routes Train : " + nb_train_routes;
        write "🚴 Routes Cycleway : " + nb_cycleway_routes;
        write "🛣️ Routes Road : " + nb_road_routes;
        write "❓ Autres : " + nb_other_routes;
        write "━━━━━━━━━━━━━━━━━━━━━━━━━";
        write "🛤️ TOTAL EXPORTÉ : " + nb_total_created;
        write "🔑 Avec ID OSM unique : " + (nb_total_created - nb_without_osm_id);
        write "⚠️ Sans ID OSM : " + nb_without_osm_id;
        write "🚏 Arrêts bus GTFS : " + nb_bus_stops;
    }
    
    // 🎯 CRÉATION ROUTE COMPLÈTE - AVEC ID CANONIQUE UNIQUE
    action create_route_complete(geometry geom) {
        string route_type;
        int routeType_num;
        rgb route_color;
        float route_width;
        
        // ══════════════════════════════════════════════════════════
        // 📥 RÉCUPÉRATION DES ATTRIBUTS OSM STANDARDS
        // ══════════════════════════════════════════════════════════
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
        
        // ══════════════════════════════════════════════════════════
        // 🔎 RÉCUPÉRATION ROBUSTE DES IDENTIFIANTS OSM
        // ══════════════════════════════════════════════════════════
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
        
        // ══════════════════════════════════════════════════════════
        // 🏷️ DÉTERMINATION DU TYPE OSM (way/relation/node)
        // ══════════════════════════════════════════════════════════
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
        
        // ══════════════════════════════════════════════════════════
        // 🔑 CONSTRUCTION DE L'ID CANONIQUE UNIQUE
        // ══════════════════════════════════════════════════════════
        string osm_uid <- "";
        if (id_str != nil and id_str != "") {
            osm_uid <- osm_type + ":" + id_str;
        } else {
            nb_without_osm_id <- nb_without_osm_id + 1;
            osm_uid <- "";
        }
        
        // ══════════════════════════════════════════════════════════
        // 📛 NOM PAR DÉFAUT INTELLIGENT
        // ══════════════════════════════════════════════════════════
        if (name = nil or name = "") {
            if (ref != nil and ref != "") {
                name <- ref;
            } else if (id_str != nil and id_str != "") {
                name <- "Route_" + id_str;
            } else {
                name <- "Route_sans_id";
            }
        }

        // ══════════════════════════════════════════════════════════
        // 🎯 CLASSIFICATION EXHAUSTIVE PAR TYPE DE TRANSPORT
        // ══════════════════════════════════════════════════════════
        
        // 🚌 BUS / TROLLEYBUS / PSV
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
        // 🚇 MÉTRO / SUBWAY
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
        // 🚴 CYCLEWAY / PISTES CYCLABLES
        else if (
            (highway = "cycleway") or (cycleway != nil) or
            (bicycle in ["designated", "yes"])
        ) {
            route_type <- "cycleway";
            routeType_num <- 10;
            route_color <- #purple;
            route_width <- 1.2;
            nb_cycleway_routes <- nb_cycleway_routes + 1;
        }
        // 🛣️ ROUTES CLASSIQUES
        else if (highway != nil and highway != "") {
            route_type <- "road";
            routeType_num <- 20;
            route_color <- #gray;
            route_width <- 1.0;
            nb_road_routes <- nb_road_routes + 1;
        }
        // ❓ AUTRES
        else {
            route_type <- "other";
            routeType_num <- 99;
            route_color <- #lightgray;
            route_width <- 0.8;
            nb_other_routes <- nb_other_routes + 1;
        }

        // ══════════════════════════════════════════════════════════
        // 📏 CALCUL DES PROPRIÉTÉS GÉOMÉTRIQUES
        // ══════════════════════════════════════════════════════════
        float length_meters <- geom.perimeter;
        int points_count <- length(geom.points);

        // ══════════════════════════════════════════════════════════
        // ✅ CRÉATION DE L'AGENT AVEC TOUS LES TAGS OSM
        // ══════════════════════════════════════════════════════════
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
            
            // 📋 Attributs OSM originaux (CORRIGÉ : tous inclus)
            highway_type::highway,
            railway_type::railway,
            route_rel::route,
            bus_access::bus,
            psv_access::psv,      // 🆕 AJOUTÉ
            ref_number::ref,
            
            // 📐 Propriétés calculées
            length_m::length_meters,
            num_points::points_count
        ];
        
        nb_total_created <- nb_total_created + 1;
    }
    
    // 🆕 VALIDATION EXPORT - Diagnostic avant export
    action validate_export {
        write "\n=== 🔍 VALIDATION EXPORT ===";
        
        list<network_route> bus_with_route_tag <- network_route where (
            each.route_type = "bus" and each.route_rel != nil
        );
        list<network_route> bus_with_bus_tag <- network_route where (
            each.route_type = "bus" and each.bus_access != nil
        );
        list<network_route> bus_with_psv_tag <- network_route where (
            each.route_type = "bus" and each.psv_access != nil
        );
        
        write "🚌 Bus avec tag 'route' : " + length(bus_with_route_tag);
        write "🚌 Bus avec tag 'bus' : " + length(bus_with_bus_tag);
        write "🚌 Bus avec tag 'psv' : " + length(bus_with_psv_tag);
        
        if length(network_route where (each.route_type = "bus")) > 0 {
            network_route sample_bus <- first(network_route where (each.route_type = "bus"));
            write "\n📋 Exemple bus :";
            write "  - route_rel : " + sample_bus.route_rel;
            write "  - bus_access : " + sample_bus.bus_access;
            write "  - psv_access : " + sample_bus.psv_access;
            write "  - highway_type : " + sample_bus.highway_type;
        }
    }
    
    // ══════════════════════════════════════════════════════════
    // 🎯 EXPORT COMPLET PAR TYPE GÉOMÉTRIQUE (SOLUTION)
    // ══════════════════════════════════════════════════════════
    action export_complete_network {
        write "\n═══════════════════════════════════════════════════════════";
        write "📦 EXPORT PAR TYPE GÉOMÉTRIQUE";
        write "═══════════════════════════════════════════════════════════";

        if empty(network_route) {
            write "❌ ERREUR : Aucun agent créé à exporter !";
            return;
        }

        // Séparation par type géométrique (utilisant perimeter et area)
        list<network_route> lines <- network_route where (
            each.shape != nil and each.shape.perimeter > 0 and each.shape.area = 0
        );
        list<network_route> points <- network_route where (
            each.shape != nil and each.shape.perimeter = 0 and each.shape.area = 0
        );
        list<network_route> polygons <- network_route where (
            each.shape != nil and each.shape.area > 0
        );

        write "\n🔍 ANALYSE DES GÉOMÉTRIES :";
        write "   📏 LineStrings : " + length(lines);
        write "   📍 Points : " + length(points);
        write "   🔷 Polygons : " + length(polygons);

        // EXPORT LINESTRINGS
        if !empty(lines) {
            write "\n━━━ 📏 EXPORT LINESTRINGS ━━━";
            string lines_path <- export_folder + "network_lines_complete.shp";

            try {
                save lines to: lines_path format: "shp" attributes: [
                    "osm_uid"::osm_uid,
                    "osm_type"::osm_type,
                    "osm_id"::osm_id,
                    "name"::name,
                    "route_type"::route_type,
                    "routeType"::routeType_num,
                    "highway"::highway_type,
                    "railway"::railway_type,
                    "route_rel"::route_rel,
                    "bus"::bus_access,
                    "psv"::psv_access,
                    "ref"::ref_number,
                    "length_m"::length_m
                ];
                write "✅ LineStrings exportées : " + length(lines);
            } catch {
                write "❌ Erreur export LineStrings";
            }
        }

        // EXPORT POINTS
        if !empty(points) {
            write "\n━━━ 📍 EXPORT POINTS ━━━";
            string points_path <- export_folder + "network_points_complete.shp";

            try {
                save points to: points_path format: "shp" attributes: [
                    "osm_uid"::osm_uid,
                    "osm_type"::osm_type,
                    "osm_id"::osm_id,
                    "name"::name,
                    "route_type"::route_type
                ];
                write "✅ Points exportés : " + length(points);
            } catch {
                write "❌ Erreur export Points";
            }
        }

        // EXPORT POLYGONS
        if !empty(polygons) {
            write "\n━━━ 🔷 EXPORT POLYGONS ━━━";
            string polygons_path <- export_folder + "network_polygons_complete.shp";

            try {
                save polygons to: polygons_path format: "shp" attributes: [
                    "osm_uid"::osm_uid,
                    "osm_type"::osm_type,
                    "osm_id"::osm_id,
                    "name"::name,
                    "route_type"::route_type
                ];
                write "✅ Polygons exportés : " + length(polygons);
            } catch {
                write "❌ Erreur export Polygons";
            }
        }

        write "\n✅ EXPORT PAR TYPE GÉOMÉTRIQUE TERMINÉ";
    }
    
    // ══════════════════════════════════════════════════════════
    // 🆕 EXPORT PAR TYPE DE TRANSPORT (CORRIGÉ)
    // ══════════════════════════════════════════════════════════
    action export_by_type_fixed {
        write "\n=== 📦 EXPORT PAR TYPE DE TRANSPORT ===";
        
        // 🚌 EXPORT BUS (par batch)
        list<network_route> bus_routes <- network_route where (each.route_type = "bus");
        write "🔍 Bus routes trouvées : " + length(bus_routes);
        
        if !empty(bus_routes) {
            do export_by_batch_robust(bus_routes, "bus_routes", 10000);
        }
        
        // 🛣️ EXPORT ROUTES PRINCIPALES (par batch)
        list<network_route> main_roads <- network_route where (each.route_type = "road");
        write "🔍 Main roads trouvées : " + length(main_roads);
        
        if !empty(main_roads) {
            do export_by_batch_robust(main_roads, "main_roads", 50000);
        }
        
        // 🚋🚇🚂 EXPORT TRANSPORT PUBLIC
        list<network_route> public_transport <- network_route where (each.route_type in ["tram", "metro", "train"]);
        if !empty(public_transport) {
            write "🔍 Transport public trouvé : " + length(public_transport);
            try {
                save public_transport to: export_folder + "public_transport.shp" format: "shp" attributes: [
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
                write "❌ Erreur export transport public";
            }
        }
        
        // 🚴 EXPORT PISTES CYCLABLES
        list<network_route> cycleways <- network_route where (each.route_type = "cycleway");
        if !empty(cycleways) {
            write "🔍 Pistes cyclables trouvées : " + length(cycleways);
            try {
                save cycleways to: export_folder + "cycleways.shp" format: "shp" attributes: [
                    "osm_uid"::osm_uid, 
                    "osm_type"::osm_type, 
                    "osm_id"::osm_id,
                    "name"::name, 
                    "highway"::highway_type,
                    "ref"::ref_number,
                    "length_m"::length_m
                ];
                write "✅ Pistes cyclables exportées : " + length(cycleways) + " → cycleways.shp";
            } catch {
                write "❌ Erreur export cycleways";
            }
        }
        
        write "🎯 EXPORT PAR TYPE TERMINÉ !";
    }
    
    // ══════════════════════════════════════════════════════════
    // 🆕 EXPORT PAR BATCH (CORRIGÉ - avec tous les tags OSM)
    // ══════════════════════════════════════════════════════════
    action export_by_batch_robust(list<network_route> routes, string filename, int batch_size) {
        write "🔄 Export robuste par batch : " + filename + " (" + length(routes) + " objets)";
        
        int total_exported <- 0;
        int batch_num <- 0;
        int current_index <- 0;
        
        list<network_route> all_valid_routes <- routes where (
            each.shape != nil and 
            each.osm_uid != nil and 
            length(each.osm_uid) > 0
        );
        write "🔍 Routes avec ID OSM valide : " + length(all_valid_routes) + "/" + length(routes);
        
        list<network_route> routes_without_id <- routes where (
            each.shape != nil and 
            (each.osm_uid = nil or length(each.osm_uid) = 0)
        );
        if !empty(routes_without_id) {
            write "⚠️ Routes sans ID OSM : " + length(routes_without_id) + " (seront exportées séparément)";
        }
        
        // EXPORT PAR BATCH DES ROUTES AVEC ID
        loop while: current_index < length(all_valid_routes) {
            int end_index <- min(current_index + batch_size - 1, length(all_valid_routes) - 1);
            list<network_route> current_batch <- [];
            
            loop i from: current_index to: end_index {
                current_batch <+ all_valid_routes[i];
            }
            
            string batch_filename <- export_folder + filename + "_part" + batch_num + ".shp";
            bool export_success <- false;
            
            // ✅ CORRIGÉ : Export avec TOUS les attributs OSM nécessaires
            try {
                save current_batch to: batch_filename format: "shp" attributes: [
                    "osm_uid"::osm_uid, 
                    "osm_type"::osm_type, 
                    "osm_id"::osm_id,
                    "name"::name, 
                    "route_type"::route_type,
                    "routeType"::routeType_num,
                    "highway"::highway_type,
                    "railway"::railway_type,
                    "route"::route_rel,
                    "bus"::bus_access,
                    "psv"::psv_access,
                    "ref"::ref_number,
                    "length_m"::length_m
                ];
                
                write "  ✅ Batch " + batch_num + " [COMPLET] : " + length(current_batch) + " objets";
                total_exported <- total_exported + length(current_batch);
                export_success <- true;
                
            } catch {
                write "  ⚠️ Erreur attributs complets, tentative attributs essentiels...";
            }
            
            if !export_success {
                try {
                    save current_batch to: batch_filename format: "shp" attributes: [
                        "osm_uid"::osm_uid,
                        "osm_type"::osm_type,
                        "osm_id"::osm_id,
                        "name"::name,
                        "type"::route_type
                    ];
                    
                    write "  ✅ Batch " + batch_num + " [MINIMAL] : " + length(current_batch) + " objets";
                    total_exported <- total_exported + length(current_batch);
                    export_success <- true;
                    
                } catch {
                    write "  ⚠️ Erreur attributs minimaux, export géométrie seule...";
                }
            }
            
            if !export_success {
                try {
                    save current_batch to: batch_filename format: "shp";
                    write "  ✅ Batch " + batch_num + " [GÉOMÉTRIE] : " + length(current_batch) + " objets";
                    total_exported <- total_exported + length(current_batch);
                    
                } catch {
                    write "  ❌ Échec total batch " + batch_num;
                }
            }
            
            current_index <- end_index + 1;
            batch_num <- batch_num + 1;
        }
        
        // ✅ CORRIGÉ : EXPORT DES ROUTES SANS ID avec route_type
        if !empty(routes_without_id) {
            string no_id_filename <- export_folder + filename + "_sans_id.shp";
            try {
                save routes_without_id to: no_id_filename format: "shp" attributes: [
                    "name"::name,
                    "route_type"::route_type,
                    "routeType"::routeType_num,
                    "highway"::highway_type,
                    "railway"::railway_type,
                    "route"::route_rel,
                    "bus"::bus_access,
                    "ref"::ref_number,
                    "length_m"::length_m
                ];
                write "  ✅ Routes sans ID exportées : " + length(routes_without_id) + " objets";
            } catch {
                write "  ⚠️ Erreur export routes sans ID";
            }
        }
        
        write "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━";
        write "📊 TOTAL " + filename + " : " + total_exported + "/" + length(all_valid_routes) + " objets exportés";
        write "📁 Fichiers créés : " + batch_num + " fichiers principaux";
        if !empty(routes_without_id) {
            write "📁 + 1 fichier pour routes sans ID";
        }
    }
}

// ══════════════════════════════════════════════════════════
// 🚌 AGENT ROUTE AVEC TOUS LES TAGS OSM (CORRIGÉ)
// ══════════════════════════════════════════════════════════
species network_route {
    // 🎨 ATTRIBUTS DE VISUALISATION
    geometry shape;
    string route_type;
    int routeType_num;
    rgb route_color;
    float route_width;
    string name;
    
    // 🔑 IDENTITÉ OSM CANONIQUE
    string osm_id;
    string osm_type;
    string osm_uid;
    
    // 📋 ATTRIBUTS OSM ORIGINAUX (CORRIGÉ)
    string highway_type;
    string railway_type;
    string route_rel;
    string bus_access;
    string psv_access;
    string ref_number;
    
    // 📐 PROPRIÉTÉS CALCULÉES
    float length_m;
    int num_points;
    
    // 🎨 ASPECTS D'AFFICHAGE
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
    
    aspect with_label {
        if shape != nil {
            draw shape color: route_color width: route_width;
            if (osm_uid != nil and length(osm_uid) > 0) {
                draw osm_uid color: #black size: 8 at: location + {0, 5};
            }
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
// 🎯 EXPÉRIMENT PRINCIPAL
// ══════════════════════════════════════════════════════════
experiment main_export type: gui {
    output {
        display "Export OSM avec ID Canonique" background: #white {
            species network_route aspect: thick;
            species bus_stop aspect: base;
            
            overlay position: {10, 10} size: {400 #px, 420 #px} background: #white transparency: 0.9 border: #black {
                draw "🔑 EXPORT OSM ID CANONIQUE (CORRIGÉ)" at: {20#px, 25#px} color: #black font: font("Arial", 14, #bold);
                
                draw "━━━━━━━━━━━━━━━━━━━━━━" at: {20#px, 45#px} color: #darkgray size: 10;
                
                draw "🔍 AGENTS CRÉÉS" at: {20#px, 65#px} color: #darkred font: font("Arial", 11, #bold);
                draw "Total : " + length(network_route) + " agents" at: {30#px, 85#px} color: #black;
                draw "Avec ID OSM : " + (nb_total_created - nb_without_osm_id) at: {30#px, 100#px} color: #darkgreen;
                draw "Sans ID OSM : " + nb_without_osm_id at: {30#px, 115#px} color: #darkred;
                draw "🚏 Arrêts bus : " + nb_bus_stops at: {30#px, 130#px} color: #red;
                
                draw "━━━━━━━━━━━━━━━━━━━━━━" at: {20#px, 150#px} color: #darkgray size: 10;
                
                draw "📊 RÉPARTITION PAR TYPE" at: {20#px, 170#px} color: #darkblue font: font("Arial", 11, #bold);
                draw "🚌 Bus : " + nb_bus_routes at: {30#px, 190#px} color: #blue;
                draw "🚋 Tram : " + nb_tram_routes at: {30#px, 205#px} color: #orange;
                draw "🚇 Métro : " + nb_metro_routes at: {30#px, 220#px} color: #red;
                draw "🚂 Train : " + nb_train_routes at: {30#px, 235#px} color: #green;
                draw "🚴 Cycleway : " + nb_cycleway_routes at: {30#px, 250#px} color: #purple;
                draw "🛣️ Roads : " + nb_road_routes at: {30#px, 265#px} color: #gray;
                draw "❓ Autres : " + nb_other_routes at: {30#px, 280#px} color: #lightgray;
                
                draw "━━━━━━━━━━━━━━━━━━━━━━" at: {20#px, 300#px} color: #darkgray size: 10;
                
                draw "📁 EXPORT TERMINÉ" at: {20#px, 320#px} color: #darkgreen font: font("Arial", 11, #bold);
                draw "✅ Shapefiles avec tags OSM" at: {30#px, 340#px} color: #green;
                draw "✅ Tags: route, bus, psv" at: {30#px, 355#px} color: #green size: 8;
                draw "✅ Format ID : type:id" at: {30#px, 370#px} color: #green size: 8;
                
                draw "━━━━━━━━━━━━━━━━━━━━━━" at: {20#px, 390#px} color: #darkgray size: 10;
                draw "● Rouge = Arrêts GTFS" at: {30#px, 410#px} color: #red size: 9;
            }
        }
        
        monitor "Routes OSM" value: length(network_route);
        monitor "Arrêts bus GTFS" value: nb_bus_stops;
        monitor "Routes bus" value: nb_bus_routes;
    }
}

experiment colored_view type: gui {
    output {
        display "Réseau Coloré par Type" background: #white {
            species network_route aspect: colored;
            species bus_stop aspect: base;
        }
        
        monitor "Arrêts bus" value: nb_bus_stops;
    }
}

experiment view_with_ids type: gui {
    output {
        display "Réseau avec ID OSM" background: #white {
            species network_route aspect: with_label;
            species bus_stop aspect: base;
        }
        
        monitor "Arrêts bus" value: nb_bus_stops;
    }
}
