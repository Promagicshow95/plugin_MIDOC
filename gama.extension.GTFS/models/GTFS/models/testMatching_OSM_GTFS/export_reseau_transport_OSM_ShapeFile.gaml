/**
 * Name: Clean_OSM_To_Shapefile
 * Author: Promagicshow95
 * Description: Export OSM vers shapefile - VERSION ID CANONIQUE UNIQUE
 * Tags: OSM, shapefile, export, network, transport
 * Date: 2025-09-29
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
    int nb_without_osm_id <- 0;
    
    // --- PARAMÈTRES D'EXPORT ---
    string export_folder <- "../../results/";

    init {
        write "=== EXPORT OSM AVEC ID CANONIQUE UNIQUE ===";
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
        
        // Debug : vérifier quelques agents
        if length(network_route) > 0 {
            write "\n🔍 === ÉCHANTILLON D'AGENTS CRÉÉS ===";
            
            network_route first_route <- first(network_route);
            write "📍 Agent 1 : " + first_route.name;
            write "   └─ Type transport : " + first_route.route_type;
            write "   └─ OSM UID : " + first_route.osm_uid;
            write "   └─ OSM Type : " + first_route.osm_type;
            write "   └─ OSM ID : " + first_route.osm_id;
            write "   └─ Highway : " + first_route.highway_type;
            write "   └─ Railway : " + first_route.railway_type;
            
            if length(network_route) > 1 {
                network_route second_route <- network_route[1];
                write "\n📍 Agent 2 : " + second_route.name;
                write "   └─ Type transport : " + second_route.route_type;
                write "   └─ OSM UID : " + second_route.osm_uid;
                write "   └─ OSM Type : " + second_route.osm_type;
                write "   └─ OSM ID : " + second_route.osm_id;
            }
        }
        
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
        // Stratégie : chercher dans plusieurs attributs possibles
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
        
        // Heuristique si le type n'est pas explicite :
        // - Si tag "route" présent → probablement une relation
        // - Si tag "highway" ou "railway" → probablement un way
        // - Par défaut → way (le plus fréquent)
        if (osm_type = nil or osm_type = "") {
            if (route != nil and route != "") {
                osm_type <- "relation";
            } else if (highway != nil or railway != nil) {
                osm_type <- "way";
            } else {
                osm_type <- "way";  // défaut
            }
        }
        
        // ══════════════════════════════════════════════════════════
        // 🔑 CONSTRUCTION DE L'ID CANONIQUE UNIQUE
        // ══════════════════════════════════════════════════════════
        // Format : "type:id" (ex: "way:123456", "relation:789012")
        string osm_uid <- "";
        if (id_str != nil and id_str != "") {
            osm_uid <- osm_type + ":" + id_str;
        } else {
            nb_without_osm_id <- nb_without_osm_id + 1;
            osm_uid <- "";  // Pas d'ID aléatoire !
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
        // 🚂 TRAIN (exclure les voies abandonnées)
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
        // ✅ CRÉATION DE L'AGENT AVEC ID CANONIQUE UNIQUE
        // ══════════════════════════════════════════════════════════
        create network_route with: [
            shape::geom,
            route_type::route_type,
            routeType_num::routeType_num,
            route_color::route_color,
            route_width::route_width,
            name::name,
            
            // 🔑 IDENTITÉ OSM CANONIQUE (TRIPLE INFORMATION)
            osm_id::id_str,         // ID brut : "123456"
            osm_type::osm_type,     // Type OSM : "way" / "relation" / "node"
            osm_uid::osm_uid,       // ID CANONIQUE : "way:123456"
            
            // 📋 Attributs OSM originaux
            highway_type::highway,
            railway_type::railway,
            route_rel::route,
            bus_access::bus,
            ref_number::ref,
            
            // 📐 Propriétés calculées
            length_m::length_meters,
            num_points::points_count
        ];
        
        nb_total_created <- nb_total_created + 1;
    }
    
    // ══════════════════════════════════════════════════════════
    // 🎯 EXPORT COMPLET VERS SHAPEFILE - AVEC ID CANONIQUE
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
                "routeType"::routeType_num,  // #️⃣ Code numérique type
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
    // 🆕 EXPORT PAR TYPE DE TRANSPORT - AVEC ID CANONIQUE
    // ══════════════════════════════════════════════════════════
    action export_by_type_fixed {
        write "\n=== 📦 EXPORT PAR TYPE DE TRANSPORT ===";
        
        // ────────────────────────────────────────────────────────
        // 🚌 EXPORT BUS (par batch pour gros volumes)
        // ────────────────────────────────────────────────────────
        list<network_route> bus_routes <- network_route where (each.route_type = "bus");
        write "🔍 Bus routes trouvées : " + length(bus_routes);
        
        if !empty(bus_routes) {
            do export_by_batch_robust(bus_routes, "bus_routes", 10000);
        }
        
        // ────────────────────────────────────────────────────────
        // 🛣️ EXPORT ROUTES PRINCIPALES (par batch pour gros volumes)
        // ────────────────────────────────────────────────────────
        list<network_route> main_roads <- network_route where (each.route_type = "road");
        write "🔍 Main roads trouvées : " + length(main_roads);
        
        if !empty(main_roads) {
            do export_by_batch_robust(main_roads, "main_roads", 50000);
        }
        
        // ────────────────────────────────────────────────────────
        // 🚋🚇🚂 EXPORT TRANSPORT PUBLIC (tram + métro + train)
        // ────────────────────────────────────────────────────────
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
                write "❌ Erreur export transport public - tentative export minimal";
                try {
                    save public_transport to: export_folder + "public_transport.shp" format: "shp" attributes: [
                        "osm_uid"::osm_uid,
                        "osm_id"::osm_id,
                        "name"::name,
                        "type"::route_type
                    ];
                    write "✅ Transport public (minimal) exporté";
                } catch {
                    write "❌ Erreur totale export transport public";
                }
            }
        }
        
        // ────────────────────────────────────────────────────────
        // 🚴 EXPORT PISTES CYCLABLES
        // ────────────────────────────────────────────────────────
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
                write "❌ Erreur export cycleways - tentative export minimal";
                try {
                    save cycleways to: export_folder + "cycleways.shp" format: "shp" attributes: [
                        "osm_uid"::osm_uid,
                        "osm_id"::osm_id,
                        "name"::name
                    ];
                    write "✅ Pistes cyclables (minimal) exportées";
                } catch {
                    write "❌ Erreur totale export cycleways";
                }
            }
        }
        
        write "🎯 EXPORT PAR TYPE TERMINÉ !";
    }
    
    // ══════════════════════════════════════════════════════════
    // 🆕 EXPORT PAR BATCH POUR GROS VOLUMES - AVEC ID CANONIQUE
    // ══════════════════════════════════════════════════════════
    action export_by_batch_robust(list<network_route> routes, string filename, int batch_size) {
        write "🔄 Export robuste par batch : " + filename + " (" + length(routes) + " objets)";
        
        int total_exported <- 0;
        int batch_num <- 0;
        int current_index <- 0;
        
        // Pré-filtrer les routes valides (shape + osm_uid non vide)
        list<network_route> all_valid_routes <- routes where (
            each.shape != nil and 
            each.osm_uid != nil and 
            length(each.osm_uid) > 0
        );
        write "🔍 Routes avec ID OSM valide : " + length(all_valid_routes) + "/" + length(routes);
        
        // Si des routes sans ID existent, les exporter séparément
        list<network_route> routes_without_id <- routes where (
            each.shape != nil and 
            (each.osm_uid = nil or length(each.osm_uid) = 0)
        );
        if !empty(routes_without_id) {
            write "⚠️ Routes sans ID OSM : " + length(routes_without_id) + " (seront exportées séparément)";
        }
        
        // ────────────────────────────────────────────────────────
        // EXPORT PAR BATCH DES ROUTES AVEC ID
        // ────────────────────────────────────────────────────────
        loop while: current_index < length(all_valid_routes) {
            int end_index <- min(current_index + batch_size - 1, length(all_valid_routes) - 1);
            list<network_route> current_batch <- [];
            
            // Créer le batch actuel
            loop i from: current_index to: end_index {
                current_batch <+ all_valid_routes[i];
            }
            
            // Export du batch
            string batch_filename <- export_folder + filename + "_part" + batch_num + ".shp";
            bool export_success <- false;
            
            // Tentative 1 : Export avec tous les attributs
            try {
                save current_batch to: batch_filename format: "shp" attributes: [
                    "osm_uid"::osm_uid, 
                    "osm_type"::osm_type, 
                    "osm_id"::osm_id,
                    "name"::name, 
                    "route_type"::route_type, 
                    "highway"::highway_type,
                    "railway"::railway_type,
                    "ref"::ref_number,
                    "length_m"::length_m
                ];
                
                write "  ✅ Batch " + batch_num + " [COMPLET] : " + length(current_batch) + " objets";
                total_exported <- total_exported + length(current_batch);
                export_success <- true;
                
            } catch {
                write "  ⚠️ Erreur attributs complets, tentative attributs essentiels...";
            }
            
            // Tentative 2 : Export avec attributs minimaux
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
            
            // Tentative 3 : Export géométrie seule
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
        
        // ────────────────────────────────────────────────────────
        // EXPORT DES ROUTES SANS ID (si elles existent)
        // ────────────────────────────────────────────────────────
        if !empty(routes_without_id) {
            string no_id_filename <- export_folder + filename + "_sans_id.shp";
            try {
                save routes_without_id to: no_id_filename format: "shp" attributes: [
                    "name"::name,
                    "route_type"::route_type,
                    "highway"::highway_type,
                    "railway"::railway_type,
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
// 🚌 AGENT ROUTE AVEC ID CANONIQUE OSM UNIQUE
// ══════════════════════════════════════════════════════════
species network_route {
    // ──────────────────────────────────────────────────────
    // 🎨 ATTRIBUTS DE VISUALISATION
    // ──────────────────────────────────────────────────────
    geometry shape;
    string route_type;        // "bus", "tram", "metro", etc.
    int routeType_num;        // Code numérique GTFS
    rgb route_color;          // Couleur d'affichage
    float route_width;        // Épaisseur ligne
    string name;              // Nom de la route
    
    // ──────────────────────────────────────────────────────
    // 🔑 IDENTITÉ OSM CANONIQUE (TRIPLE INFORMATION)
    // ──────────────────────────────────────────────────────
    string osm_id;     // ID brut : "123456"
    string osm_type;   // Type OSM : "way" / "relation" / "node"
    string osm_uid;    // 🌟 ID CANONIQUE : "way:123456" (CLÉ PRIMAIRE)
    
    // ──────────────────────────────────────────────────────
    // 📋 ATTRIBUTS OSM ORIGINAUX
    // ──────────────────────────────────────────────────────
    string highway_type;   // Type de highway OSM
    string railway_type;   // Type de railway OSM
    string route_rel;      // Type de relation route
    string bus_access;     // Accès bus
    string ref_number;     // Référence/Numéro de ligne
    
    // ──────────────────────────────────────────────────────
    // 📐 PROPRIÉTÉS CALCULÉES
    // ──────────────────────────────────────────────────────
    float length_m;    // Longueur en mètres
    int num_points;    // Nombre de points de la géométrie
    
    // ──────────────────────────────────────────────────────
    // 🎨 ASPECTS D'AFFICHAGE
    // ──────────────────────────────────────────────────────
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
// 🎯 EXPÉRIMENT PRINCIPAL - EXPORT COMPLET
// ══════════════════════════════════════════════════════════
experiment main_export type: gui {
    output {
        display "Export OSM avec ID Canonique" background: #white {
            species network_route aspect: thick;
            
            overlay position: {10, 10} size: {400 #px, 380 #px} background: #white transparency: 0.9 border: #black {
                draw "🔑 EXPORT OSM ID CANONIQUE" at: {20#px, 25#px} color: #black font: font("Arial", 14, #bold);
                
                draw "━━━━━━━━━━━━━━━━━━━━━━" at: {20#px, 45#px} color: #darkgray size: 10;
                
                draw "🔍 AGENTS CRÉÉS" at: {20#px, 65#px} color: #darkred font: font("Arial", 11, #bold);
                draw "Total : " + length(network_route) + " agents" at: {30#px, 85#px} color: #black;
                draw "Avec ID OSM : " + (nb_total_created - nb_without_osm_id) at: {30#px, 100#px} color: #darkgreen;
                draw "Sans ID OSM : " + nb_without_osm_id at: {30#px, 115#px} color: #darkred;
                
                draw "━━━━━━━━━━━━━━━━━━━━━━" at: {20#px, 135#px} color: #darkgray size: 10;
                
                draw "📊 RÉPARTITION PAR TYPE" at: {20#px, 155#px} color: #darkblue font: font("Arial", 11, #bold);
                draw "🚌 Bus : " + nb_bus_routes at: {30#px, 175#px} color: #blue;
                draw "🚋 Tram : " + nb_tram_routes at: {30#px, 190#px} color: #orange;
                draw "🚇 Métro : " + nb_metro_routes at: {30#px, 205#px} color: #red;
                draw "🚂 Train : " + nb_train_routes at: {30#px, 220#px} color: #green;
                draw "🚴 Cycleway : " + nb_cycleway_routes at: {30#px, 235#px} color: #purple;
                draw "🛣️ Roads : " + nb_road_routes at: {30#px, 250#px} color: #gray;
                draw "❓ Autres : " + nb_other_routes at: {30#px, 265#px} color: #lightgray;
                
                draw "━━━━━━━━━━━━━━━━━━━━━━" at: {20#px, 285#px} color: #darkgray size: 10;
                
                draw "📁 EXPORT TERMINÉ" at: {20#px, 305#px} color: #darkgreen font: font("Arial", 11, #bold);
                draw "✅ Shapefiles avec ID canonique" at: {30#px, 325#px} color: #green;
                draw "✅ Dossier : ../../results/" at: {30#px, 340#px} color: #green size: 8;
                draw "✅ Format ID : type:id" at: {30#px, 355#px} color: #green size: 8;
            }
        }
    }
}

// ══════════════════════════════════════════════════════════
// 🎯 EXPÉRIMENT AVEC COULEURS PAR TYPE
// ══════════════════════════════════════════════════════════
experiment colored_view type: gui {
    output {
        display "Réseau Coloré par Type" background: #white {
            species network_route aspect: colored;
            
            overlay position: {10, 10} size: {280 #px, 220 #px} background: #white transparency: 0.9 border: #black {
                draw "🎨 LÉGENDE COULEURS" at: {15#px, 25#px} color: #black font: font("Arial", 13, #bold);
                draw "━━━━━━━━━━━━━━━━━━" at: {15#px, 45#px} color: #darkgray size: 9;
                draw "🚌 Bleu = Bus" at: {20#px, 65#px} color: #blue font: font("Arial", 11);
                draw "🚋 Orange = Tram" at: {20#px, 85#px} color: #orange font: font("Arial", 11);
                draw "🚇 Rouge = Métro" at: {20#px, 105#px} color: #red font: font("Arial", 11);
                draw "🚂 Vert = Train" at: {20#px, 125#px} color: #green font: font("Arial", 11);
                draw "🚴 Violet = Cycleway" at: {20#px, 145#px} color: #purple font: font("Arial", 11);
                draw "🛣️ Gris = Routes" at: {20#px, 165#px} color: #gray font: font("Arial", 11);
                draw "❓ Noir = Autres" at: {20#px, 185#px} color: #black font: font("Arial", 11);
                draw "━━━━━━━━━━━━━━━━━━" at: {15#px, 200#px} color: #darkgray size: 9;
            }
        }
    }
}

// ══════════════════════════════════════════════════════════
// 🎯 EXPÉRIMENT AVEC AFFICHAGE DES ID
// ══════════════════════════════════════════════════════════
experiment view_with_ids type: gui {
    output {
        display "Réseau avec ID OSM" background: #white {
            species network_route aspect: with_label;
            
            overlay position: {10, 10} size: {300 #px, 140 #px} background: #white transparency: 0.9 border: #black {
                draw "🔍 AFFICHAGE ID OSM" at: {15#px, 25#px} color: #black font: font("Arial", 13, #bold);
                draw "━━━━━━━━━━━━━━━━━━━━━" at: {15#px, 45#px} color: #darkgray size: 9;
                draw "Format : type:id" at: {20#px, 65#px} color: #darkblue font: font("Arial", 10);
                draw "Exemple : way:123456" at: {20#px, 85#px} color: #darkgreen font: font("Arial", 10);
                draw "Total agents : " + length(network_route) at: {20#px, 105#px} color: #black font: font("Arial", 10, #bold);
                draw "Avec ID : " + (nb_total_created - nb_without_osm_id) at: {20#px, 120#px} color: #darkgreen font: font("Arial", 9);
            }
        }
    }
}