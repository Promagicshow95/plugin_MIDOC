/**
 * Name: Clean_OSM_To_Shapefile_FINAL_BBOX_FIXED_CORRECTED
 * Author: Promagicshow95
 * Description: Export OSM - VERSION FINALE CORRIGÉE (calculs BBOX dans init)
 * Tags: OSM, shapefile, export, network, transport
 * Date: 2025-10-27
 * 
 * CORRECTIFS APPLIQUÉS :
 * ✅ Tous les calculs géométriques déplacés dans init (était la cause du NullPointerException)
 * ✅ Noms d'attributs shapefile raccourcis à 10 caractères max
 * ✅ Typage strict pour osm_data_to_generate
 */

model Clean_OSM_To_Shapefile_Final_BBOX_Fixed_Corrected

global {
    // ══════════════════════════════════════════════════════════
    // 📁 FICHIERS
    // ══════════════════════════════════════════════════════════
    file data_file <- shape_file("../../includes/shapeFileNantes.shp");
    geometry shape <- envelope(data_file);
    
    // ══════════════════════════════════════════════════════════
    // ✅ DÉCLARATIONS UNIQUEMENT (calculs dans init)
    // ══════════════════════════════════════════════════════════
    float minx_corrected;
    float maxx_corrected;
    float miny_corrected;
    float maxy_corrected;
    string adress;
    
    // ✅ Typage strict pour éviter les erreurs
    map<string, list<string>> osm_data_to_generate <- [
        "highway"::[],
        "railway"::[],
        "route"::[],
        "cycleway"::[],
        "bus"::[],
        "psv"::[],
        "public_transport"::[],
        "waterway"::[]
    ];
    
    // ══════════════════════════════════════════════════════════
    // 📊 VARIABLES STATISTIQUES
    // ══════════════════════════════════════════════════════════
    int nb_bus_routes <- 0;
    int nb_tram_routes <- 0;
    int nb_metro_routes <- 0;
    int nb_train_routes <- 0;
    int nb_cycleway_routes <- 0;
    int nb_road_routes <- 0;
    int nb_ferry_routes <- 0;
    int nb_other_routes <- 0;
    int nb_total_created <- 0;
    int nb_without_osm_id <- 0;
    int nb_closed_ways_converted <- 0;
    
    string export_folder <- "../../results1/";

    // ══════════════════════════════════════════════════════════
    // 🚀 INITIALISATION - TOUS LES CALCULS ICI
    // ══════════════════════════════════════════════════════════
    init {
        write "=== EXPORT OSM FINAL (BBOX + CLASSIFICATION CORRIGÉES) ===";
        write "🔑 Système d'identification : osm_type:osm_id";
        
        // ✅ CALCUL BBOX ROBUSTE - MAINTENANT DANS INIT
        write "🔄 Calcul BBOX avec tampon 800m...";
        
        geometry env_local <- envelope(data_file);
        geometry env_3857 <- CRS_transform(env_local, "EPSG:3857");
        geometry env_3857_buf <- env_3857 buffer 800.0 #m;
        geometry env_wgs <- CRS_transform(env_3857_buf, "EPSG:4326");
        
        list<float> xs <- env_wgs.points collect each.x;
        list<float> ys <- env_wgs.points collect each.y;
        
        float minx <- min(xs);
        float maxx <- max(xs);
        float miny <- min(ys);
        float maxy <- max(ys);
        
        // Correction avec opérateur ternaire
        minx_corrected <- (minx < maxx) ? minx : maxx;
        maxx_corrected <- (minx < maxx) ? maxx : minx;
        miny_corrected <- (miny < maxy) ? miny : maxy;
        maxy_corrected <- (miny < maxy) ? maxy : miny;
        
        // Construction URL Overpass
        adress <- "http://overpass-api.de/api/xapi_meta?*[bbox=" + 
                  minx_corrected + "," + miny_corrected + "," + 
                  maxx_corrected + "," + maxy_corrected + "]";
        
        write "📦 BBOX WGS84 : [" + (minx_corrected with_precision 5) + "," + 
              (miny_corrected with_precision 5) + "] → [" + 
              (maxx_corrected with_precision 5) + "," + (maxy_corrected with_precision 5) + "]";
        write "🔄 Tampon emprise : 800m (EPSG:3857)";
        
        // Validation Nantes
        point nantes <- {-1.5536, 47.2184};
        bool nantes_inside <- (nantes.x >= minx_corrected) and (nantes.x <= maxx_corrected) and 
                              (nantes.y >= miny_corrected) and (nantes.y <= maxy_corrected);
        write "🔍 Nantes (-1.5536, 47.2184) dans bbox ? " + nantes_inside;
        if (!nantes_inside) {
            write "⚠️ ATTENTION : Nantes hors bbox ! Vérifiez shapeFileNantes.shp";
        }
        
        // ✅ CHARGEMENT OSM
        file<geometry> osm_geometries <- osm_file<geometry>(adress, osm_data_to_generate);
        write "✅ Géométries OSM chargées : " + length(osm_geometries);
        
        // ✅ CRÉATION DES AGENTS
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
        
        // ✅ EXPORT
        do export_complete_network;
        do export_by_type_fixed;
        
        // ✅ STATISTIQUES FINALES
        write "\n=== 📊 STATISTIQUES RÉSEAU EXPORTÉ ===";
        write "🚌 Routes Bus : " + nb_bus_routes;
        write "🚋 Routes Tram : " + nb_tram_routes; 
        write "🚇 Routes Métro : " + nb_metro_routes;
        write "🚂 Routes Train : " + nb_train_routes;
        write "🚴 Routes Cycleway : " + nb_cycleway_routes;
        write "🛣️ Routes Road : " + nb_road_routes;
        write "⛴️ Routes Ferry : " + nb_ferry_routes;
        write "❓ Autres : " + nb_other_routes;
        write "━━━━━━━━━━━━━━━━━━━━━━━━━";
        write "🛤️ TOTAL EXPORTÉ : " + nb_total_created;
        write "🔑 Avec ID OSM unique : " + (nb_total_created - nb_without_osm_id);
        write "⚠️ Sans ID OSM : " + nb_without_osm_id;
    }
    
    // ══════════════════════════════════════════════════════════
    // 🎯 CRÉATION ROUTE COMPLÈTE - AVEC ID CANONIQUE UNIQUE
    // ══════════════════════════════════════════════════════════
    action create_route_complete(geometry geom) {
        string route_type;
        int routeType_num;
        rgb route_color;
        float route_width;
        
        // Récupération des attributs OSM standards
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
        
        string busway_left <- (geom.attributes["busway:left"] as string);
        string busway_right <- (geom.attributes["busway:right"] as string);
        string busway <- (geom.attributes["busway"] as string);
        string bus_lanes <- (geom.attributes["bus:lanes"] as string);
        string psv_lanes <- (geom.attributes["psv:lanes"] as string);
        
        // Variables pour tests "contains"
        string r <- railway;
        if (r = nil) { r <- ""; }
        
        string rt <- route;
        if (rt = nil) { rt <- ""; }
        
        string rtm <- route_master;
        if (rtm = nil) { rtm <- ""; }
        
        // Détection tram
        bool is_tram <- (railway = "tram") or (route = "tram") or (route_master = "tram") or
                        (r contains "tram") or (r contains "light_rail") or
                        (rt contains "tram") or (rt contains "light_rail") or
                        (rtm contains "tram") or (rtm contains "light_rail");
        
        // Détection métro
        bool is_metro <- (railway = "subway") or (railway = "metro") or 
                         (route = "subway") or (route = "metro") or
                         (r contains "subway") or (r contains "metro");
        
        bool is_rail <- (railway != nil) and (railway != "");
        
        bool is_excluded <- (r contains "abandoned") or (r contains "platform") or 
                            (r contains "tram_stop") or (r contains "disused") or
                            (r contains "construction") or (r contains "proposed") or
                            (r contains "razed") or (r contains "dismantled");
        
        bool has_bus_lane <- (busway_left in ["lane", "track"]) or 
                            (busway_right in ["lane", "track"]) or 
                            (busway in ["lane", "track"]) or 
                            (bus_lanes != nil and bus_lanes != "") or
                            (psv_lanes != nil and psv_lanes != "");
        
        // Récupération robuste des identifiants OSM
        string id_str <- (geom.attributes["@id"] as string);
        if (id_str = nil or id_str = "") { id_str <- (geom.attributes["id"] as string); }
        if (id_str = nil or id_str = "") { id_str <- (geom.attributes["osm_id"] as string); }
        if (id_str = nil or id_str = "") { id_str <- (geom.attributes["way_id"] as string); }
        if (id_str = nil or id_str = "") { id_str <- (geom.attributes["rel_id"] as string); }
        if (id_str = nil or id_str = "") { id_str <- (geom.attributes["relation_id"] as string); }
        
        // Détermination du type OSM
        string osm_type <- (geom.attributes["@type"] as string);
        if (osm_type = nil or osm_type = "") { osm_type <- (geom.attributes["type"] as string); }
        
        if (osm_type = nil or osm_type = "") {
            if (route != nil and route != "") {
                osm_type <- "relation";
            } else if (highway != nil or railway != nil) {
                osm_type <- "way";
            } else {
                osm_type <- "way";
            }
        }
        
        // Construction ID canonique
        string osm_uid <- "";
        if (id_str != nil and id_str != "") {
            osm_uid <- osm_type + ":" + id_str;
        } else {
            nb_without_osm_id <- nb_without_osm_id + 1;
            osm_uid <- "";
        }
        
        // Nom par défaut
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
        // 🎨 CLASSIFICATION PAR TYPE (ordre important : tram avant train)
        // ══════════════════════════════════════════════════════════
        if (
            ((route = "bus") or (route = "trolleybus") or (route_master = "bus") or
             (highway in ["busway", "bus_guideway"]) or (bus in ["yes", "designated"]) or 
             (psv = "yes") or has_bus_lane) 
            and !is_rail
        ) {
            route_type <- "bus";
            routeType_num <- 3;
            route_color <- #blue;
            route_width <- 2.5;
            nb_bus_routes <- nb_bus_routes + 1;
        }
        else if (is_tram and !is_excluded) {
            route_type <- "tram";
            routeType_num <- 0;
            route_color <- #orange;
            route_width <- 2.0;
            nb_tram_routes <- nb_tram_routes + 1;
        }
        else if (is_metro and !is_excluded) {
            route_type <- "metro";
            routeType_num <- 1;
            route_color <- #red;
            route_width <- 2.0;
            nb_metro_routes <- nb_metro_routes + 1;
        }
        else if (is_rail and !is_excluded and !is_tram and !is_metro) {
            route_type <- "train";
            routeType_num <- 2;
            route_color <- #green;
            route_width <- 1.8;
            nb_train_routes <- nb_train_routes + 1;
        }
        else if (route = "ferry") {
            route_type <- "ferry";
            routeType_num <- 4;
            route_color <- #cyan;
            route_width <- 1.5;
            nb_ferry_routes <- nb_ferry_routes + 1;
        }
        else if ((highway = "cycleway") or (cycleway != nil) or (bicycle in ["designated", "yes"])) {
            route_type <- "cycleway";
            routeType_num <- 10;
            route_color <- #purple;
            route_width <- 1.2;
            nb_cycleway_routes <- nb_cycleway_routes + 1;
        }
        else if (highway != nil and highway != "") {
            route_type <- "road";
            routeType_num <- 20;
            route_color <- #gray;
            route_width <- 1.0;
            nb_road_routes <- nb_road_routes + 1;
        }
        else {
            route_type <- "other";
            routeType_num <- 99;
            route_color <- #lightgray;
            route_width <- 0.8;
            nb_other_routes <- nb_other_routes + 1;
        }
        
        // Calcul propriétés géométriques
        float length_meters <- geom.perimeter;
        int points_count <- length(geom.points);
        
        // ✅ CRÉATION AGENT avec tous les attributs
        create network_route with: [
            shape::geom,
            route_type::route_type,
            routeType_num::routeType_num,
            route_color::route_color,
            route_width::route_width,
            name::name,
            osm_id::id_str,
            osm_type::osm_type,
            osm_uid::osm_uid,
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
    
    // ══════════════════════════════════════════════════════════
    // 📦 EXPORT RÉSEAU COMPLET
    // ══════════════════════════════════════════════════════════
    action export_complete_network {
        write "\n=== 📦 EXPORT VERS SHAPEFILE ===";
        
        if empty(network_route) {
            write "❌ ERREUR : Aucun agent créé !";
            return;
        }
        
        string shapefile_path <- export_folder + "network_transport_complete.shp";
        
        try {
            // ✅ NOMS RACCOURCIS À 10 CARACTÈRES MAX
            save network_route to: shapefile_path format: "shp" attributes: [
                "osm_uid"::osm_uid,
                "osm_type"::osm_type,
                "osm_id"::osm_id,
                "name"::name,
                "routetype"::route_type,
                "rt_num"::routeType_num,
                "highway"::highway_type,
                "railway"::railway_type,
                "ref"::ref_number,
                "len_m"::length_m
            ];
            
            write "✅ EXPORT COMPLET RÉUSSI : " + shapefile_path;
            write "📊 " + length(network_route) + " routes exportées";
            
        } catch {
            write "❌ Erreur d'export complet - tentative minimale";
            
            try {
                save network_route to: shapefile_path format: "shp" attributes: [
                    "osm_uid"::osm_uid,
                    "osm_type"::osm_type,
                    "osm_id"::osm_id,
                    "name"::name,
                    "routetype"::route_type
                ];
                write "✅ EXPORT MINIMAL RÉUSSI";
            } catch {
                write "❌ Échec - Export géométrie seule";
                save network_route to: shapefile_path format: "shp";
                write "✅ EXPORT GÉOMÉTRIE SEULE";
            }
        }
    }
    
    // ══════════════════════════════════════════════════════════
    // 📦 EXPORT PAR TYPE
    // ══════════════════════════════════════════════════════════
    action export_by_type_fixed {
        write "\n=== 📦 EXPORT PAR TYPE ===";
        
        // Bus
        list<network_route> bus_routes <- network_route where (each.route_type = "bus");
        write "🔍 Bus : " + length(bus_routes);
        if !empty(bus_routes) {
            do export_by_batch_robust(bus_routes, "bus_routes", 10000);
        }
        
        // Routes principales
        list<network_route> main_roads <- network_route where (each.route_type = "road");
        write "🔍 Roads : " + length(main_roads);
        if !empty(main_roads) {
            do export_by_batch_robust(main_roads, "main_roads", 50000);
        }
        
        // Transport public (tram, metro, train)
        list<network_route> public_transport <- network_route where (each.route_type in ["tram", "metro", "train"]);
        if !empty(public_transport) {
            write "🔍 Transport public : " + length(public_transport);
            try {
                save public_transport to: export_folder + "public_transport.shp" format: "shp" attributes: [
                    "osm_uid"::osm_uid,
                    "osm_type"::osm_type,
                    "osm_id"::osm_id,
                    "name"::name,
                    "routetype"::route_type,
                    "railway"::railway_type,
                    "ref"::ref_number,
                    "len_m"::length_m
                ];
                write "✅ Transport public exporté";
            } catch {
                write "❌ Erreur export transport public";
            }
        }
        
        // Cycleways
        list<network_route> cycleways <- network_route where (each.route_type = "cycleway");
        if !empty(cycleways) {
            write "🔍 Cycleways : " + length(cycleways);
            try {
                save cycleways to: export_folder + "cycleways.shp" format: "shp" attributes: [
                    "osm_uid"::osm_uid,
                    "osm_type"::osm_type,
                    "osm_id"::osm_id,
                    "name"::name,
                    "highway"::highway_type,
                    "ref"::ref_number,
                    "len_m"::length_m
                ];
                write "✅ Cycleways exportés";
            } catch {
                write "❌ Erreur export cycleways";
            }
        }
        
        // Ferries
        list<network_route> ferries <- network_route where (each.route_type = "ferry");
        if !empty(ferries) {
            write "🔍 Ferries : " + length(ferries);
            try {
                save ferries to: export_folder + "ferries.shp" format: "shp" attributes: [
                    "osm_uid"::osm_uid,
                    "osm_type"::osm_type,
                    "osm_id"::osm_id,
                    "name"::name,
                    "ref"::ref_number,
                    "len_m"::length_m
                ];
                write "✅ Ferries exportés";
            } catch {
                write "❌ Erreur export ferries";
            }
        }
        
        write "🎯 EXPORT PAR TYPE TERMINÉ !";
    }
    
    // ══════════════════════════════════════════════════════════
    // 📦 EXPORT PAR BATCH (pour grands fichiers)
    // ══════════════════════════════════════════════════════════
    action export_by_batch_robust(list<network_route> routes, string filename, int batch_size) {
        write "🔄 Export batch : " + filename;
        
        int total_exported <- 0;
        int batch_num <- 0;
        int current_index <- 0;
        
        // Séparer routes avec/sans ID
        list<network_route> all_valid_routes <- routes where (
            each.shape != nil and 
            each.osm_uid != nil and 
            length(each.osm_uid) > 0
        );
        
        list<network_route> routes_without_id <- routes where (
            each.shape != nil and 
            (each.osm_uid = nil or length(each.osm_uid) = 0)
        );
        
        // Export par batch
        loop while: current_index < length(all_valid_routes) {
            int end_index <- min(current_index + batch_size - 1, length(all_valid_routes) - 1);
            list<network_route> current_batch <- [];
            
            loop i from: current_index to: end_index {
                current_batch <+ all_valid_routes[i];
            }
            
            string batch_filename <- export_folder + filename + "_part" + batch_num + ".shp";
            bool export_success <- false;
            
            try {
                // ✅ NOMS RACCOURCIS
                save current_batch to: batch_filename format: "shp" attributes: [
                    "osm_uid"::osm_uid,
                    "osm_type"::osm_type,
                    "osm_id"::osm_id,
                    "name"::name,
                    "routetype"::route_type,
                    "highway"::highway_type,
                    "railway"::railway_type,
                    "ref"::ref_number,
                    "len_m"::length_m
                ];
                write "  ✅ Batch " + batch_num + " : " + length(current_batch);
                total_exported <- total_exported + length(current_batch);
                export_success <- true;
            } catch {
                write "  ⚠️ Erreur batch " + batch_num;
            }
            
            // Fallback minimal si erreur
            if !export_success {
                try {
                    save current_batch to: batch_filename format: "shp" attributes: [
                        "osm_uid"::osm_uid,
                        "osm_type"::osm_type,
                        "osm_id"::osm_id,
                        "name"::name,
                        "routetype"::route_type
                    ];
                    write "  ✅ Batch " + batch_num + " [MINIMAL]";
                    total_exported <- total_exported + length(current_batch);
                    export_success <- true;
                } catch {
                    write "  ⚠️ Erreur minimale";
                }
            }
            
            // Fallback géométrie seule
            if !export_success {
                try {
                    save current_batch to: batch_filename format: "shp";
                    write "  ✅ Batch " + batch_num + " [GEOM]";
                    total_exported <- total_exported + length(current_batch);
                } catch {
                    write "  ❌ Échec total batch " + batch_num;
                }
            }
            
            current_index <- end_index + 1;
            batch_num <- batch_num + 1;
        }
        
        // Export routes sans ID
        if !empty(routes_without_id) {
            string no_id_filename <- export_folder + filename + "_sans_id.shp";
            try {
                save routes_without_id to: no_id_filename format: "shp" attributes: [
                    "name"::name,
                    "routetype"::route_type,
                    "highway"::highway_type,
                    "railway"::railway_type,
                    "len_m"::length_m
                ];
                write "  ✅ Routes sans ID exportées";
            } catch {
                write "  ⚠️ Erreur sans ID";
            }
        }
        
        write "📊 TOTAL : " + total_exported + "/" + length(all_valid_routes);
    }
}

// ══════════════════════════════════════════════════════════
// 🚌 AGENT ROUTE AVEC ID CANONIQUE OSM UNIQUE
// ══════════════════════════════════════════════════════════
species network_route {
    // Attributs de visualisation
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
    
    // Attributs OSM originaux
    string highway_type;
    string railway_type;
    string route_rel;
    string bus_access;
    string ref_number;
    
    // Propriétés calculées
    float length_m;
    int num_points;
    
    // Aspects d'affichage
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
            } else if route_type = "ferry" {
                display_color <- #cyan;
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
// 🎯 EXPÉRIMENT 1 : EXPORT PRINCIPAL
// ══════════════════════════════════════════════════════════
experiment main_export type: gui {
    output {
        display "Export OSM FINAL CORRIGÉ" background: #white {
            species network_route aspect: thick;
            
            overlay position: {10, 10} size: {460 #px, 440 #px} background: #white transparency: 0.9 border: #black {
                draw "🔑 EXPORT OSM CORRIGÉ" at: {20#px, 25#px} color: #black font: font("Arial", 14, #bold);
                draw "━━━━━━━━━━━━━━━━━━━━━━" at: {20#px, 45#px} color: #darkgray size: 10;
                
                draw "✅ CORRECTIONS APPLIQUÉES" at: {20#px, 65#px} color: #darkgreen font: font("Arial", 11, #bold);
                draw "🎯 BBOX robuste (min/max) ✓" at: {30#px, 85#px} color: #green size: 9;
                draw "🎯 Calculs BBOX dans init ✓" at: {30#px, 100#px} color: #green size: 9;
                draw "🎯 Classification = + contains ✓" at: {30#px, 115#px} color: #green size: 9;
                draw "🎯 Noms attributs < 10 car ✓" at: {30#px, 130#px} color: #green size: 9;
                
                draw "━━━━━━━━━━━━━━━━━━━━━━" at: {20#px, 150#px} color: #darkgray size: 10;
                
                draw "🔍 AGENTS CRÉÉS" at: {20#px, 170#px} color: #darkred font: font("Arial", 11, #bold);
                draw "Total : " + length(network_route) + " agents" at: {30#px, 190#px} color: #black;
                draw "Avec ID OSM : " + (nb_total_created - nb_without_osm_id) at: {30#px, 205#px} color: #darkgreen;
                draw "Sans ID OSM : " + nb_without_osm_id at: {30#px, 220#px} color: #darkred;
                
                draw "━━━━━━━━━━━━━━━━━━━━━━" at: {20#px, 240#px} color: #darkgray size: 10;
                
                draw "📊 RÉPARTITION PAR TYPE" at: {20#px, 260#px} color: #darkblue font: font("Arial", 11, #bold);
                draw "🚌 Bus : " + nb_bus_routes at: {30#px, 280#px} color: #blue;
                draw "🚋 Tram : " + nb_tram_routes at: {30#px, 295#px} color: #orange font: font("Arial", 10, #bold);
                draw "🚇 Métro : " + nb_metro_routes at: {30#px, 310#px} color: #red;
                draw "🚂 Train : " + nb_train_routes at: {30#px, 325#px} color: #green;
                draw "⛴️ Ferry : " + nb_ferry_routes at: {30#px, 340#px} color: #cyan;
                draw "🚴 Cycleway : " + nb_cycleway_routes at: {30#px, 355#px} color: #purple;
                draw "🛣️ Roads : " + nb_road_routes at: {30#px, 370#px} color: #gray;
                draw "❓ Autres : " + nb_other_routes at: {30#px, 385#px} color: #lightgray;
                
                draw "━━━━━━━━━━━━━━━━━━━━━━" at: {20#px, 405#px} color: #darkgray size: 10;
                draw "✅ NullPointerException corrigé" at: {30#px, 425#px} color: #darkgreen font: font("Arial", 9, #bold);
            }
        }
    }
}

// ══════════════════════════════════════════════════════════
// 🎯 EXPÉRIMENT 2 : VUE COLORÉE PAR TYPE
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
                draw "⛴️ Cyan = Ferry" at: {20#px, 165#px} color: #cyan font: font("Arial", 11);
                draw "🛣️ Gris = Routes" at: {20#px, 185#px} color: #gray font: font("Arial", 11);
                draw "❓ Noir = Autres" at: {20#px, 205#px} color: #black font: font("Arial", 11);
            }
        }
    }
}

// ══════════════════════════════════════════════════════════
// 🎯 EXPÉRIMENT 3 : VUE AVEC ID OSM
// ══════════════════════════════════════════════════════════
experiment view_with_ids type: gui {
    output {
        display "Réseau avec ID OSM" background: #white {
            species network_route aspect: with_label;
            
            overlay position: {10, 10} size: {320 #px, 160 #px} background: #white transparency: 0.9 border: #black {
                draw "🔍 AFFICHAGE ID OSM" at: {15#px, 25#px} color: #black font: font("Arial", 13, #bold);
                draw "━━━━━━━━━━━━━━━━━━━━━" at: {15#px, 45#px} color: #darkgray size: 9;
                draw "Format : type:id" at: {20#px, 65#px} color: #darkblue font: font("Arial", 10);
                draw "Exemple : way:123456" at: {20#px, 85#px} color: #darkgreen font: font("Arial", 10);
                draw "Total agents : " + length(network_route) at: {20#px, 105#px} color: #black font: font("Arial", 10, #bold);
                draw "Avec ID : " + (nb_total_created - nb_without_osm_id) at: {20#px, 125#px} color: #darkgreen font: font("Arial", 9);
                draw "Sans ID : " + nb_without_osm_id at: {20#px, 145#px} color: #darkred font: font("Arial", 9);
            }
        }
    }
}