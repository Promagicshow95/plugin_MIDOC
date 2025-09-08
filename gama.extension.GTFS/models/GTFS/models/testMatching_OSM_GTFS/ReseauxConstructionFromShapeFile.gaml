/**
 * Name: Network_From_Shapefiles
 * Author: Promagicshow95
 * Description: Reconstitution du réseau de transport depuis les shapefiles exportés
 * Tags: shapefile, network, transport, bus, reload
 * Date: 2025-08-21
 * 
 * COMPATIBILITÉ:
 * Ce modèle est conçu pour charger les shapefiles créés par Clean_OSM_To_Shapefile.
 * Mapping des attributs:
 * - Export "osm_id" → Load read("osm_id")
 * - Export "name" → Load read("name") 
 * - Export "route_type" → Load read("route_type")
 * - Export "highway" → Load read("highway")
 * - Export "railway" → Load read("railway")
 * - Export "length_m" → Load read("length_m")
 */

model Network_From_Shapefiles

global {
    // --- CONFIGURATION FICHIERS ---
    string results_folder <- "../../results/";
    
    // ✅ AJOUT : FICHIER DE RÉFÉRENCE POUR L'ENVELOPPE
    file data_file <- shape_file("../../includes/shapeFileHanoishp.shp");
    geometry shape <- envelope(data_file);  // ✅ DÉFINITION ENVELOPPE MONDE
    
    // --- VARIABLES STATISTIQUES ---
    int total_bus_routes <- 0;
    int total_main_roads <- 0;
    int total_public_transport <- 0;
    int total_cycleways <- 0;
    int total_network_elements <- 0;
    
    // --- PARAMÈTRES D'AFFICHAGE ---
    bool show_bus <- true;
    bool show_roads <- false;  // Désactivé par défaut (trop volumineux)
    bool show_public_transport <- true;
    bool show_cycleways <- true;
    
    // --- PARAMÈTRES PERFORMANCE ---
    int max_roads_to_load <- 5;  // Nombre max de fichiers routes à charger

    init {
        write "=== RECONSTRUCTION RÉSEAU DEPUIS SHAPEFILES ===";
        
        // 🚌 CHARGEMENT RÉSEAU BUS (TOUS LES PARTS) - AUTO-DÉTECTION
        do load_bus_network_robust;
        
        // 🚇 CHARGEMENT TRANSPORT PUBLIC
        if show_public_transport {
            do load_public_transport;
        }
        
        // 🚴 CHARGEMENT PISTES CYCLABLES
        if show_cycleways {
            do load_cycleways;
        }
        
        // 🛣️ CHARGEMENT ROUTES PRINCIPALES (OPTIONNEL - GROS VOLUME)
        if show_roads {
            do load_main_roads;
        }
        
        // 🌍 VALIDER L'ENVELOPPE DU MONDE
        do validate_world_envelope;
        
        // Statistiques finales
        write "\n=== RÉSEAU RECONSTRUIT ===";
        write "🚌 Routes Bus : " + total_bus_routes;
        write "🚇 Transport Public : " + total_public_transport;
        write "🚴 Pistes Cyclables : " + total_cycleways;
        write "🛣️ Routes Principales : " + total_main_roads;
        write "🌐 TOTAL ÉLÉMENTS : " + total_network_elements;
        
        write "\n=== AGENTS CRÉÉS ===";
        write "🚌 Bus routes agents : " + length(bus_route);
        write "🚇 Public transport agents : " + length(public_transport_route);
        write "🚴 Cycleway agents : " + length(cycleway_route);
        write "🛣️ Main road agents : " + length(main_road);
        
        // 🔍 VALIDATION DE LA COMPATIBILITÉ
        do validate_loaded_data;
        
        // 🔍 DIAGNOSTIC GÉOMÉTRIES
        do diagnose_geometry_issues;
    }
    
    // 🚌 CHARGEMENT RÉSEAU BUS COMPLET - VERSION ROBUSTE
    action load_bus_network_robust {
        write "\n🚌 === CHARGEMENT RÉSEAU BUS (AUTO-DÉTECTION) ===";
        
        int bus_parts_loaded <- 0;
        int bus_routes_count <- 0;
        int i <- 0;
        bool continue_loading <- true;
        
        // Boucle jusqu'à ce qu'on ne trouve plus de fichiers
        loop while: continue_loading and i < 30 {  // Sécurité max 30 fichiers
            string filename <- results_folder + "bus_routes_part" + i + ".shp";
            
            try {
                file shape_file_bus <- shape_file(filename);
                
                // ✅ CHARGEMENT CORRIGÉ DES ATTRIBUTS - COMPATIBLE AVEC EXPORT
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
                // Fichier non trouvé, on arrête
                write "  ℹ️ Fin détection à part" + i + " (fichier non trouvé)";
                continue_loading <- false;
            }
        }
        
        total_bus_routes <- bus_routes_count;
        total_network_elements <- total_network_elements + bus_routes_count;
        
        write "📊 TOTAL BUS : " + bus_routes_count + " routes en " + bus_parts_loaded + " fichiers";
        
        // 🔍 VÉRIFICATION GÉOMÉTRIES
        if length(bus_route) > 0 {
            int valid_geometries <- 0;
            int invalid_geometries <- 0;
            
            loop route over: bus_route {
                if route.shape != nil and length(route.shape.points) > 1 {
                    valid_geometries <- valid_geometries + 1;
                } else {
                    invalid_geometries <- invalid_geometries + 1;
                }
            }
            
            write "🔍 Géométries valides : " + valid_geometries + "/" + length(bus_route);
            write "❌ Géométries invalides : " + invalid_geometries;
        }
    }
    
    // 🚇 CHARGEMENT TRANSPORT PUBLIC
    action load_public_transport {
        write "\n🚇 === CHARGEMENT TRANSPORT PUBLIC ===";
        
        string filename <- results_folder + "public_transport.shp";
        
        try {
            file shape_file_pt <- shape_file(filename);
            
            create public_transport_route from: shape_file_pt with: [
                route_name::string(read("name")),
                osm_id::string(read("osm_id")),
                route_type::string(read("route_type")),
                railway_type::string(read("railway")),
                length_meters::float(read("length_m"))
            ];
            
            total_public_transport <- length(shape_file_pt);
            total_network_elements <- total_network_elements + total_public_transport;
            
            write "✅ " + total_public_transport + " routes de transport public chargées";
            
        } catch {
            write "❌ Erreur chargement transport public : " + filename;
        }
    }
    
    // 🚴 CHARGEMENT PISTES CYCLABLES
    action load_cycleways {
        write "\n🚴 === CHARGEMENT PISTES CYCLABLES ===";
        
        string filename <- results_folder + "cycleways.shp";
        
        try {
            file shape_file_cycle <- shape_file(filename);
            
            create cycleway_route from: shape_file_cycle with: [
                route_name::string(read("name")),
                osm_id::string(read("osm_id")),
                highway_type::string(read("highway")),
                length_meters::float(read("length_m"))
            ];
            
            total_cycleways <- length(shape_file_cycle);
            total_network_elements <- total_network_elements + total_cycleways;
            
            write "✅ " + total_cycleways + " pistes cyclables chargées";
            
        } catch {
            write "❌ Erreur chargement pistes cyclables : " + filename;
        }
    }
    
    // 🛣️ CHARGEMENT ROUTES PRINCIPALES (OPTIONNEL)
    action load_main_roads {
        write "\n🛣️ === CHARGEMENT ROUTES PRINCIPALES ===";
        write "⚠️ ATTENTION : Chargement de gros volumes...";
        
        int roads_parts_loaded <- 0;
        int roads_count <- 0;
        
        // Charger tous les fichiers main_roads_partX.shp
        loop i from: 0 to: min(12, max_roads_to_load) {  // Ajusté selon vos fichiers (0-12)
            string filename <- results_folder + "main_roads_part" + i + ".shp";
            
            try {
                file shape_file_roads <- shape_file(filename);
                
                create main_road from: shape_file_roads with: [
                    route_name::string(read("name")),
                    osm_id::string(read("osm_id")),
                    route_type::string(read("route_type")),
                    highway_type::string(read("highway")),
                    length_meters::float(read("length_m"))
                ];
                
                int roads_in_file <- length(shape_file_roads);
                roads_count <- roads_count + roads_in_file;
                roads_parts_loaded <- roads_parts_loaded + 1;
                
                write "  ✅ Part " + i + " : " + roads_in_file + " routes";
                
            } catch {
                write "  ❌ Erreur lecture part " + i;
                // Continue avec le fichier suivant
            }
        }
        
        total_main_roads <- roads_count;
        total_network_elements <- total_network_elements + roads_count;
        
        write "📊 TOTAL ROUTES : " + roads_count + " en " + roads_parts_loaded + " fichiers";
    }
    
    // 🌍 VALIDER L'ENVELOPPE DU MONDE
    action validate_world_envelope {
        write "\n🌍 === VALIDATION ENVELOPPE MONDE ===";
        
        if shape != nil {
            write "✅ Enveloppe définie depuis shapeFileHanoishp.shp";
            write "📏 Dimensions: " + shape.width + " x " + shape.height;
            write "📍 Centre: " + shape.location;
            
            // Vérifier que les données sont dans l'enveloppe
            if length(bus_route) > 0 {
                bus_route sample_bus <- first(bus_route);
                if sample_bus.shape != nil {
                    bool inside <- shape covers sample_bus.shape.location;
                    write "🔍 Données bus dans l'enveloppe: " + (inside ? "✅ OUI" : "❌ NON");
                    
                    if !inside {
                        write "⚠️ PROBLÈME: Les données sont hors de l'enveloppe définie";
                        write "💡 Solution: Agrandissez l'enveloppe ou vérifiez les coordonnées";
                        
                        // Proposer une enveloppe élargie
                        geometry extended_envelope <- envelope(shape + sample_bus.shape);
                        write "🔧 Enveloppe suggérée: " + extended_envelope;
                    }
                }
            }
        } else {
            write "❌ PROBLÈME: Aucune enveloppe définie";
            write "💡 Vérifiez le fichier ../../includes/shapeFileHanoishp.shp";
            
            // Fallback: créer enveloppe à partir des données
            do create_envelope_from_data;
        }
    }
    
    // 🔧 CRÉER ENVELOPPE À PARTIR DES DONNÉES CHARGÉES
    action create_envelope_from_data {
        write "\n🔧 === CRÉATION ENVELOPPE DEPUIS DONNÉES ===";
        
        list<geometry> all_shapes <- [];
        
        // Collecter toutes les géométries valides
        loop route over: bus_route {
            if route.shape != nil {
                all_shapes <+ route.shape;
            }
        }
        
        loop route over: public_transport_route {
            if route.shape != nil {
                all_shapes <+ route.shape;
            }
        }
        
        loop route over: cycleway_route {
            if route.shape != nil {
                all_shapes <+ route.shape;
            }
        }
        
        if !empty(all_shapes) {
            geometry union_geom <- union(all_shapes);
            shape <- envelope(union_geom);
            write "✅ Enveloppe créée depuis les données: " + shape;
            write "📏 Dimensions: " + shape.width + " x " + shape.height;
        } else {
            write "❌ Impossible de créer une enveloppe - aucune géométrie valide";
            // Enveloppe par défaut (coordonnées approximatives de Hanoi)
            shape <- rectangle(100000, 100000) at_location {587500, -2320000};
            write "⚠️ Utilisation enveloppe par défaut";
        }
    }
    
    // 🔍 VALIDATION DES DONNÉES CHARGÉES
    action validate_loaded_data {
        write "\n🔍 === VALIDATION DONNÉES CHARGÉES ===";
        
        if length(bus_route) > 0 {
            bus_route sample_bus <- first(bus_route);
            write "✅ Échantillon Bus:";
            write "  - Nom: " + (sample_bus.route_name != nil ? sample_bus.route_name : "VIDE");
            write "  - OSM ID: " + (sample_bus.osm_id != nil ? sample_bus.osm_id : "VIDE");
            write "  - Type: " + (sample_bus.route_type != nil ? sample_bus.route_type : "VIDE");
            write "  - Highway: " + (sample_bus.highway_type != nil ? sample_bus.highway_type : "VIDE");
            write "  - Longueur: " + sample_bus.length_meters + "m";
        }
        
        if length(public_transport_route) > 0 {
            public_transport_route sample_pt <- first(public_transport_route);
            write "✅ Échantillon Transport Public:";
            write "  - Nom: " + (sample_pt.route_name != nil ? sample_pt.route_name : "VIDE");
            write "  - Type: " + (sample_pt.route_type != nil ? sample_pt.route_type : "VIDE");
            write "  - Railway: " + (sample_pt.railway_type != nil ? sample_pt.railway_type : "VIDE");
        }
        
        if length(cycleway_route) > 0 {
            cycleway_route sample_cycle <- first(cycleway_route);
            write "✅ Échantillon Cycleway:";
            write "  - Nom: " + (sample_cycle.route_name != nil ? sample_cycle.route_name : "VIDE");
            write "  - Highway: " + (sample_cycle.highway_type != nil ? sample_cycle.highway_type : "VIDE");
        }
        
        write "🎯 VALIDATION TERMINÉE - Vérifiez qu'aucun champ n'est VIDE";
    }
    
    // 🔍 DIAGNOSTIC COMPLET DES GÉOMÉTRIES
    action diagnose_geometry_issues {
        write "\n🔍 === DIAGNOSTIC GÉOMÉTRIES ===";
        
        int total_valid_shapes <- 0;
        int total_invalid_shapes <- 0;
        int total_nil_shapes <- 0;
        
        // Diagnostic Bus
        if length(bus_route) > 0 {
            loop route over: bus_route {
                if route.shape = nil {
                    total_nil_shapes <- total_nil_shapes + 1;
                } else if length(route.shape.points) > 1 {
                    total_valid_shapes <- total_valid_shapes + 1;
                } else {
                    total_invalid_shapes <- total_invalid_shapes + 1;
                }
            }
            
            write "🚌 Bus - Shapes valides: " + total_valid_shapes;
            write "🚌 Bus - Shapes nil: " + total_nil_shapes;
            write "🚌 Bus - Shapes invalides: " + total_invalid_shapes;
            
            if total_valid_shapes > 0 {
                bus_route sample <- first(bus_route where (each.shape != nil));
                if sample != nil {
                    write "🔍 Échantillon géométrie bus: " + sample.shape;
                    write "🔍 Points: " + length(sample.shape.points);
                    write "🔍 Localisation: " + sample.shape.location;
                }
            }
        }
        
        // Diagnostic général
        write "\n📊 RÉSUMÉ GÉOMÉTRIES:";
        write "✅ Valides: " + total_valid_shapes;
        write "❌ Nil: " + total_nil_shapes;
        write "⚠️ Invalides: " + total_invalid_shapes;
        
        if total_nil_shapes > 0 or total_invalid_shapes > 0 {
            write "\n⚠️ PROBLÈME DÉTECTÉ:";
            write "Les géométries ne sont pas chargées correctement.";
            write "Solutions possibles:";
            write "1. Vérifiez que les shapefiles contiennent des géométries";
            write "2. GAMA charge automatiquement les géométries depuis les shapefiles";
            write "3. Vérifiez le système de coordonnées";
        } else {
            write "✅ Toutes les géométries sont valides !";
        }
    }
    
    // 🔧 VERSION ALTERNATIVE - CHARGEMENT AVEC RECHARGEMENT
    action reload_bus_network {
        write "\n🔧 === RECHARGEMENT RÉSEAU BUS ===";
        
        // Effacer les agents existants
        ask bus_route {
            do die;
        }
        
        // Réinitialiser les compteurs
        total_bus_routes <- 0;
        total_network_elements <- 0;
        
        // Recharger
        do load_bus_network_robust;
        
        write "🔄 Rechargement terminé : " + length(bus_route) + " agents bus";
    }
    
    // 🔧 ACTION POUR TESTER LE RECHARGEMENT DEPUIS L'EXPERIMENT
    action test_reload_from_experiment {
        do reload_bus_network;
        
        // Validation immédiate
        if length(bus_route) > 0 {
            bus_route test_route <- first(bus_route);
            if test_route.shape != nil {
                write "✅ Rechargement réussi - géométries présentes";
            } else {
                write "⚠️ Rechargement OK mais géométries manquantes";
            }
        } else {
            write "❌ Échec du rechargement - aucun agent créé";
        }
    }
}

// 🚌 AGENT ROUTE BUS
species bus_route {
    string route_name;
    string osm_id;
    string route_type;
    string highway_type;
    float length_meters;
    
    aspect default {
        if shape != nil {
            draw shape color: #blue width: 2.0;
        } else {
            // Fallback si pas de géométrie - dessiner un point
            draw circle(10) color: #blue at: location;
        }
    }
    
    aspect thick {
        if shape != nil {
            draw shape color: #blue width: 3.0;
        } else {
            // Fallback - point plus gros
            draw circle(15) color: #blue at: location;
        }
    }
    
    aspect labeled {
        if shape != nil {
            draw shape color: #blue width: 3.0;
            if route_name != nil and route_name != "" and route_name != "name" {
                draw route_name size: 12 color: #black at: location + {0, 10};
            }
        } else {
            draw circle(15) color: #blue at: location;
            if route_name != nil and route_name != "" {
                draw route_name size: 10 color: #black at: location + {0, 20};
            }
        }
    }
    
    aspect debug {
        // Aspect pour diagnostic
        if shape != nil {
            draw shape color: #green width: 4.0;
            draw "✅" size: 15 color: #green at: location;
        } else {
            draw circle(20) color: #red at: location;
            draw "❌" size: 15 color: #red at: location;
        }
    }
}

// 🚇 AGENT TRANSPORT PUBLIC
species public_transport_route {
    string route_name;
    string osm_id;
    string route_type;
    string railway_type;
    float length_meters;
    
    aspect default {
        rgb display_color;
        if route_type = "metro" {
            display_color <- #red;
        } else if route_type = "tram" {
            display_color <- #orange;
        } else if route_type = "train" {
            display_color <- #green;
        } else {
            display_color <- #darkred;
        }
        
        if shape != nil {
            draw shape color: display_color width: 2.5;
        } else {
            draw circle(12) color: display_color at: location;
        }
    }
}

// 🚴 AGENT PISTE CYCLABLE
species cycleway_route {
    string route_name;
    string osm_id;
    string highway_type;
    float length_meters;
    
    aspect default {
        if shape != nil {
            draw shape color: #purple width: 1.5;
        } else {
            draw circle(8) color: #purple at: location;
        }
    }
}

// 🛣️ AGENT ROUTE PRINCIPALE
species main_road {
    string route_name;
    string osm_id;
    string route_type;
    string highway_type;
    float length_meters;
    
    aspect default {
        if shape != nil {
            draw shape color: #gray width: 1.0;
        } else {
            draw circle(5) color: #gray at: location;
        }
    }
    
    aspect thin {
        if shape != nil {
            draw shape color: #lightgray width: 0.5;
        } else {
            draw circle(3) color: #lightgray at: location;
        }
    }
}

// 🎯 EXPÉRIMENT RÉSEAU BUS UNIQUEMENT
experiment bus_network_only type: gui {
    parameter "Afficher routes bus" var: show_bus <- true;
    parameter "Afficher transport public" var: show_public_transport <- true;
    parameter "Afficher pistes cyclables" var: show_cycleways <- true;
    parameter "Afficher routes principales" var: show_roads <- false;
    
    output {
        display "Réseau Bus Hanoi" background: #white type: 2d {
            species bus_route aspect: thick;
            species public_transport_route aspect: default;
            species cycleway_route aspect: default;
            
            overlay position: {10, 10} size: {300 #px, 240 #px} background: #white transparency: 0.9 border: #black {
                draw "=== RÉSEAU RECONSTRUIT ===" at: {10#px, 20#px} color: #black font: font("Arial", 12, #bold);
                draw "🚌 Bus : " + length(bus_route) + " routes" at: {20#px, 40#px} color: #blue;
                draw "🚇 Transport Public : " + length(public_transport_route) at: {20#px, 60#px} color: #red;
                draw "🚴 Pistes Cyclables : " + length(cycleway_route) at: {20#px, 80#px} color: #purple;
                draw "📁 Source : shapefiles exportés" at: {20#px, 110#px} color: #gray size: 9;
                draw "✅ Réseau opérationnel" at: {20#px, 130#px} color: #green;
                draw "🎯 Prêt pour simulation" at: {20#px, 150#px} color: #darkgreen;
                
                // Status géométries
                if length(bus_route) > 0 {
                    bus_route test_route <- first(bus_route);
                    string status <- test_route.shape != nil ? "✅ Géométries OK" : "❌ Géométries manquantes";
                    rgb status_color <- test_route.shape != nil ? #green : #red;
                    draw status at: {20#px, 175#px} color: status_color size: 9;
                }
                
                // Debug info
                if length(bus_route) > 0 {
                    bus_route sample_bus <- first(bus_route);
                    draw "Debug: " + sample_bus.route_name at: {20#px, 200#px} color: #gray size: 8;
                    draw "OSM ID: " + sample_bus.osm_id at: {20#px, 215#px} color: #gray size: 8;
                }
            }
        }
    }
}

// 🎯 EXPÉRIMENT TEST SIMPLE
experiment test_simple type: gui {
    // Action accessible depuis l'experiment
    action reload_buses {
        ask world {
            do test_reload_from_experiment;
        }
    }
    
    action fit_to_data {
        ask world {
            do create_envelope_from_data;
        }
    }
    
    // ✅ USER_COMMANDS AU BON NIVEAU
    user_command "Recharger réseau bus" action: reload_buses;
    user_command "Fit to Data" action: fit_to_data;
    
    output {
        display "Test Simple" background: #white type: 2d {
            species bus_route aspect: thick;
            
            overlay position: {10, 10} size: {280 #px, 260 #px} background: #white transparency: 0.9 border: #black {
                draw "=== TEST SIMPLE ===" at: {10#px, 20#px} color: #black font: font("Arial", 12, #bold);
                draw "Bus: " + length(bus_route) at: {20#px, 45#px} color: #blue;
                
                if length(bus_route) > 0 {
                    bus_route first_bus <- first(bus_route);
                    string status <- first_bus.shape != nil ? "✅ Visible" : "❌ Pas de géométrie";
                    draw status at: {20#px, 70#px} color: (first_bus.shape != nil ? #green : #red);
                    
                    if first_bus.shape != nil {
                        draw "📍 Coord: " + first_bus.shape.location at: {20#px, 90#px} color: #black size: 8;
                        draw "📏 Points: " + length(first_bus.shape.points) at: {20#px, 105#px} color: #black size: 8;
                        
                        // Vérifier si dans l'enveloppe
                        if shape != nil {
                            bool inside <- shape covers first_bus.shape.location;
                            string envelope_status <- inside ? "✅ Dans enveloppe" : "❌ Hors enveloppe";
                            draw envelope_status at: {20#px, 120#px} color: (inside ? #green : #red) size: 8;
                        }
                    } else {
                        draw "🔄 Menu → 'Recharger réseau bus'" at: {20#px, 90#px} color: #orange size: 8;
                    }
                } else {
                    draw "❌ Aucun agent bus chargé" at: {20#px, 70#px} color: #red;
                    draw "🔄 Menu → 'Recharger réseau bus'" at: {20#px, 90#px} color: #orange size: 8;
                }
                
                // Status enveloppe
                if shape != nil {
                    draw "🌍 Enveloppe: " + int(shape.width) + "x" + int(shape.height) at: {20#px, 145#px} color: #darkgreen size: 8;
                } else {
                    draw "❌ Pas d'enveloppe définie" at: {20#px, 145#px} color: #red size: 8;
                }
                
                draw "💡 Solutions si pas visible:" at: {20#px, 170#px} color: #gray size: 8;
                draw "1. Menu → Recharger réseau bus" at: {30#px, 185#px} color: #gray size: 8;
                draw "2. Zoomez/déplacez la vue" at: {30#px, 200#px} color: #gray size: 8;
                draw "3. Fit to data (Ctrl+F)" at: {30#px, 215#px} color: #gray size: 8;
                draw "4. Vérifiez ../../includes/shapeFileHanoishp.shp" at: {30#px, 230#px} color: #gray size: 8;
                draw "5. Ou essayez diagnostic_simple" at: {30#px, 245#px} color: #gray size: 8;
            }
        }
    }
}

// 🎯 EXPÉRIMENT DE DIAGNOSTIC SIMPLE
experiment diagnostic_simple type: gui {
    action force_reload {
        ask world {
            do test_reload_from_experiment;
        }
    }
    
    action test_geometry_loading {
        ask world {
            write "\n🔧 === TEST CHARGEMENT GÉOMÉTRIES ===";
            
            // Test avec un seul fichier
            string test_file <- "../../results/bus_routes_part0.shp";
            
            try {
                file shape_file_test <- shape_file(test_file);
                write "✅ Fichier trouvé : " + test_file;
                write "📊 Objets dans le fichier : " + length(shape_file_test);
                
                // Test création d'un agent
                create bus_route from: shape_file_test with: [
                    route_name::string(read("name")),
                    osm_id::string(read("osm_id")),
                    route_type::string(read("route_type"))
                ] {
                    write "🔍 Agent créé : " + name;
                    write "🔍 Géométrie : " + (shape != nil ? "✅ Présente" : "❌ Absente");
                    if shape != nil {
                        write "🔍 Points : " + length(shape.points);
                        write "🔍 Location : " + shape.location;
                    }
                }
                
            } catch {
                write "❌ Erreur : Impossible de charger " + test_file;
            }
        }
    }
    
    action fit_to_data_diag {
        ask world {
            do create_envelope_from_data;
        }
    }
    
    // ✅ USER_COMMANDS AU BON NIVEAU
    user_command "Force Reload" action: force_reload;
    user_command "Test Geometry Loading" action: test_geometry_loading;
    user_command "Fit to Data" action: fit_to_data_diag;
    
    output {
        display "Diagnostic" background: #white type: 2d {
            species bus_route aspect: debug;
            
            overlay position: {10, 10} size: {350 #px, 320 #px} background: #white transparency: 0.9 border: #black {
                draw "=== DIAGNOSTIC RÉSEAU ===" at: {10#px, 20#px} color: #black font: font("Arial", 12, #bold);
                
                draw "🔍 ÉTAT ACTUEL:" at: {20#px, 45#px} color: #darkblue font: font("Arial", 10, #bold);
                draw "Bus agents : " + length(bus_route) at: {30#px, 65#px} color: #blue;
                
                if length(bus_route) > 0 {
                    bus_route test_bus <- first(bus_route);
                    string geo_status <- test_bus.shape != nil ? "✅ GÉOMÉTRIE OK" : "❌ GÉOMÉTRIE NIL";
                    draw geo_status at: {30#px, 85#px} color: (test_bus.shape != nil ? #green : #red);
                    
                    if test_bus.shape != nil {
                        draw "📍 Coordonnées: " + test_bus.shape.location at: {30#px, 105#px} color: #black size: 8;
                        draw "📏 Nb points: " + length(test_bus.shape.points) at: {30#px, 120#px} color: #black size: 8;
                        
                        // Status enveloppe
                        if shape != nil {
                            bool inside <- shape covers test_bus.shape.location;
                            string env_status <- inside ? "✅ Dans enveloppe" : "❌ Hors enveloppe";
                            draw env_status at: {30#px, 135#px} color: (inside ? #green : #red) size: 8;
                        }
                    }
                } else {
                    draw "Aucun agent chargé" at: {30#px, 85#px} color: #red;
                }
                
                // Informations enveloppe
                draw "🌍 ENVELOPPE MONDE:" at: {20#px, 160#px} color: #darkgreen font: font("Arial", 10, #bold);
                if shape != nil {
                    draw "Dimensions: " + int(shape.width) + " x " + int(shape.height) at: {30#px, 180#px} color: #black size: 8;
                    draw "Centre: " + shape.location at: {30#px, 195#px} color: #black size: 8;
                } else {
                    draw "❌ Pas d'enveloppe définie" at: {30#px, 180#px} color: #red size: 8;
                }
                
                draw "🛠️ ACTIONS MENU:" at: {20#px, 220#px} color: #darkorange font: font("Arial", 10, #bold);
                draw "• Force Reload - Recharge tout" at: {30#px, 240#px} color: #gray size: 8;
                draw "• Test Geometry - Test 1 fichier" at: {30#px, 255#px} color: #gray size: 8;
                
                draw "💡 VISUALISATION:" at: {20#px, 280#px} color: #darkgreen font: font("Arial", 10, #bold);
                draw "✅ = Géométrie OK, ❌ = Problème" at: {30#px, 300#px} color: #gray size: 8;
            }
        }
    }
}
// 🎯 EXPÉRIMENT RÉSEAU COMPLET (ATTENTION AUX PERFORMANCES)
experiment full_network type: gui {
    parameter "Afficher routes bus" var: show_bus <- true;
    parameter "Afficher transport public" var: show_public_transport <- true;
    parameter "Afficher pistes cyclables" var: show_cycleways <- true;
    parameter "Afficher routes principales" var: show_roads <- false;
    parameter "Max fichiers routes" var: max_roads_to_load min: 1 max: 15;
    
    action reload_all {
        ask world {
            do test_reload_from_experiment;
        }
    }
    
    action fit_to_data_full {
        ask world {
            do create_envelope_from_data;
        }
    }
    
    // ✅ USER_COMMANDS AU BON NIVEAU
    user_command "Recharger réseau" action: reload_all;
    user_command "Fit to Data" action: fit_to_data_full;
    
    output {
        display "Réseau Complet Hanoi" background: #white type: 2d {
            species main_road aspect: thin;      // Routes en arrière-plan (fines)
            species bus_route aspect: thick;     // Bus en évidence
            species public_transport_route aspect: default;
            species cycleway_route aspect: default;
            
            overlay position: {10, 10} size: {350 #px, 320 #px} background: #white transparency: 0.9 border: #black {
                draw "=== RÉSEAU TRANSPORT HANOI ===" at: {10#px, 20#px} color: #black font: font("Arial", 12, #bold);
                
                draw "🚌 Bus : " + length(bus_route) at: {20#px, 45#px} color: #blue;
                draw "🚇 Transport Public : " + length(public_transport_route) at: {20#px, 65#px} color: #red;
                draw "🚴 Pistes Cyclables : " + length(cycleway_route) at: {20#px, 85#px} color: #purple;
                draw "🛣️ Routes : " + length(main_road) at: {20#px, 105#px} color: #gray;
                
                int total_displayed <- length(bus_route) + length(public_transport_route) + length(cycleway_route) + length(main_road);
                draw "📊 TOTAL : " + total_displayed + " éléments" at: {20#px, 130#px} color: #black font: font("Arial", 10, #bold);
                
                // Status géométries détaillé
                if length(bus_route) > 0 {
                    bus_route test_route <- first(bus_route);
                    string status <- test_route.shape != nil ? "✅ Géométries OK" : "❌ Géométries manquantes";
                    rgb status_color <- test_route.shape != nil ? #green : #red;
                    draw status at: {20#px, 155#px} color: status_color size: 9;
                    
                    if test_route.shape != nil {
                        // Compter les géométries valides
                        int valid_count <- 0;
                        loop route over: bus_route {
                            if route.shape != nil {
                                valid_count <- valid_count + 1;
                            }
                        }
                        float percentage <- (valid_count / length(bus_route)) * 100;
                        draw "📊 Géométries valides: " + valid_count + "/" + length(bus_route) + " (" + int(percentage) + "%)" at: {20#px, 175#px} color: #black size: 8;
                    } else {
                        draw "→ Menu → 'Recharger réseau'" at: {20#px, 175#px} color: #orange size: 8;
                    }
                } else {
                    draw "❌ Aucun agent chargé" at: {20#px, 155#px} color: #red;
                    draw "→ Menu → 'Recharger réseau'" at: {20#px, 175#px} color: #orange size: 8;
                }
                
                draw "📁 Source : " + results_folder at: {20#px, 200#px} color: #gray size: 8;
                draw "✅ Chargement depuis shapefiles" at: {20#px, 220#px} color: #green size: 8;
                
                // Status enveloppe
                if shape != nil {
                    draw "🌍 Enveloppe: " + int(shape.width) + "x" + int(shape.height) at: {20#px, 240#px} color: #darkgreen size: 8;
                } else {
                    draw "❌ Pas d'enveloppe définie" at: {20#px, 240#px} color: #red size: 8;
                }
                
                if show_roads {
                    draw "⚠️ Mode performance réduite" at: {20#px, 260#px} color: #orange size: 8;
                } else {
                    draw "💡 Routes désactivées (performance)" at: {20#px, 260#px} color: #blue size: 8;
                }
                
                draw "🔧 Problèmes ? → diagnostic_simple" at: {20#px, 280#px} color: #red size: 8;
                draw "🔄 Ou Menu → 'Recharger réseau'" at: {20#px, 300#px} color: #blue size: 8;
            }
        }
    }
}