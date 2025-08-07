model ShapeStopProjectionTest_Nantes

global {
    // === CONFIGURATION DE LA PROJECTION ===
    // Utilisation de Web Mercator comme dans votre exemple, ou Lambert-93 pour la France
    string projection_crs <- "EPSG:3857"; // Web Mercator
    // Alternative pour la France : "EPSG:2154" (Lambert-93)
    
    // === FICHIERS DE DONNÉES ===
    gtfs_file gtfs_f <- gtfs_file("../../includes/nantes_gtfs");
    shape_file boundary_shp <- shape_file("../../includes/shapeFileNantes.shp");
    geometry shape <- envelope(boundary_shp);
    
    // === VARIABLES DE TEST CORRIGÉES ===
    int total_stops <- 0;
    int total_shapes <- 0;
    float coherence_tolerance <- 100.0; // Distance en mètres pour considérer qu'un stop est "sur" une shape
    int coherent_stops <- 0;
    int valid_stops <- 0; //  Arrêts avec correspondance RouteType valide
    int invalid_stops <- 0; //  Arrêts sans correspondance RouteType
    list<bus_stop> problematic_stops <- [];
    list<bus_stop> invalid_stops_list <- []; // NOUVEAU: Liste des arrêts invalides
    
    // === VARIABLES POUR ROUTETYPE ===
    map<int, int> routetype_stats <- []; // routeType -> nombre d'arrêts
    map<int, int> shape_routetype_stats <- []; // routeType -> nombre de shapes
    map<int, string> routetype_names <- [
        0::"Tram", 1::"Métro", 2::"Train", 3::"Bus", 4::"Ferry", 
        5::"Câble", 6::"Gondole", 7::"Funiculaire", 11::"Trolleybus", 12::"Monorail"
    ];
    
    // === STATISTIQUES DE COHÉRENCE CORRIGÉES ===
    float min_distance_to_shape <- 999999.0;
    float max_distance_to_shape <- 0.0;
    float avg_distance_to_shape <- 0.0;
    float total_distance_sum <- 0.0;
    
    init {
        write "=== TEST DE COHÉRENCE SPATIALE SHAPE-STOP AVEC ROUTETYPE STRICT ===";
        write "📍 Projection utilisée : " + projection_crs;
        write "📏 Tolérance de cohérence : " + string(coherence_tolerance) + " mètres";
        write "🎯 Mode : Correspondance RouteType STRICTE (pas de fallback)";
        write "";
        
        // Définir la projection avant de charger les données
        write "🔧 Configuration de la projection...";
        
        write "📂 Chargement des données GTFS depuis : tisseo_gtfs_v2";
        
        // === CRÉATION DES ARRÊTS ===
        write "🚏 Création des arrêts de transport...";
        create bus_stop from: gtfs_f {
            // Personnalisation de l'affichage
            if stopName != nil {
                display_name <- stopName;
                // Identifier les arrêts importants
                if contains(stopName, "Capitole") or contains(stopName, "Gare") or 
                   contains(stopName, "Centre") or contains(stopName, "Station") {
                    size <- 150.0;
                    is_important <- true;
                }
            } else {
                display_name <- "Arrêt_" + stopId;
            }
            
            // Configuration selon le routeType
            if routeType != nil {
                switch routeType {
                    match 0 { type_color <- #blue; type_name <- "Tram"; }
                    match 1 { type_color <- #orange; type_name <- "Métro"; }
                    match 2 { type_color <- #red; type_name <- "Train"; }
                    match 3 { type_color <- #green; type_name <- "Bus"; }
                    match 4 { type_color <- #cyan; type_name <- "Ferry"; }
                    match 5 { type_color <- #magenta; type_name <- "Câble"; }
                    match 6 { type_color <- #yellow; type_name <- "Gondole"; }
                    match 7 { type_color <- #purple; type_name <- "Funiculaire"; }
                    match 11 { type_color <- #darkgreen; type_name <- "Trolleybus"; }
                    match 12 { type_color <- #brown; type_name <- "Monorail"; }
                    default { type_color <- #gray; type_name <- "Autre(" + routeType + ")"; }
                }
            } else {
                type_color <- #gray;
                type_name <- "Inconnu";
            }
            
            // Couleur initiale
            color <- type_color;
        }
        
        // Compter APRÈS la création
        total_stops <- length(bus_stop);
        write "✅ " + string(total_stops) + " arrêts créés";
        
        // === CRÉATION DES SHAPES ===
        write "📐 Création des formes de transport...";
        create transport_shape from: gtfs_f {
            // Configuration selon le routeType
            if routeType != nil {
                switch routeType {
                    match 0 { line_color <- #blue; }      // Tram
                    match 1 { line_color <- #orange; }    // Métro  
                    match 2 { line_color <- #red; }       // Train
                    match 3 { line_color <- #green; }     // Bus
                    match 4 { line_color <- #cyan; }      // Ferry
                    match 5 { line_color <- #magenta; }   // Câble
                    match 6 { line_color <- #yellow; }    // Gondole
                    match 7 { line_color <- #purple; }    // Funiculaire
                    match 11 { line_color <- #darkgreen; } // Trolleybus
                    match 12 { line_color <- #brown; }    // Monorail
                    default { line_color <- #gray; }
                }
            } else {
                // Fallback: couleur selon l'ID de la shape
                int shape_hash <- int(shapeId) mod 8;
                switch shape_hash {
                    match 0 { line_color <- #blue; }
                    match 1 { line_color <- #red; }
                    match 2 { line_color <- #green; }
                    match 3 { line_color <- #orange; }
                    match 4 { line_color <- #purple; }
                    match 5 { line_color <- #cyan; }
                    match 6 { line_color <- #magenta; }
                    default { line_color <- #gray; }
                }
            }
        }

        // Compter APRÈS la création
        total_shapes <- length(transport_shape);
        write "✅ " + string(total_shapes) + " formes de transport créées";
        
        // === INITIALISATION DES AGENTS ===
        ask bus_stop { 
            do customInit;
        }
        
        ask transport_shape {
            do customInit;
        }
        
        // === STATISTIQUES DES ROUTETYPES ===
        ask bus_stop {
            if routeType != nil {
                if not(myself.routetype_stats contains_key routeType) {
                    myself.routetype_stats[routeType] <- 0;
                }
                myself.routetype_stats[routeType] <- myself.routetype_stats[routeType] + 1;
            }
        }
        
        ask transport_shape {
            if routeType != nil {
                if not(myself.shape_routetype_stats contains_key routeType) {
                    myself.shape_routetype_stats[routeType] <- 0;
                }
                myself.shape_routetype_stats[routeType] <- myself.shape_routetype_stats[routeType] + 1;
            }
        }
        
        write "📊 Statistiques initiales des RouteTypes:";
        loop rt over: routetype_stats.keys {
            string type_name <- routetype_names contains_key rt ? routetype_names[rt] : ("Type_" + rt);
            int stop_count <- routetype_stats[rt];
            int shape_count <- shape_routetype_stats contains_key rt ? shape_routetype_stats[rt] : 0;
            write "   " + type_name + " (" + rt + "): " + stop_count + " arrêts, " + shape_count + " shapes";
        }
        
        write "🚀 Modèle initialisé - Analyse de cohérence stricte en cours...";
    }
    
    // === ANALYSE DE COHÉRENCE SPATIALE CORRIGÉE (ROUTETYPE STRICT) ===
    reflex analyze_coherence when: cycle = 1 {
        write "=== ANALYSE DE COHÉRENCE SPATIALE (ROUTETYPE STRICT) ===";
        
        total_distance_sum <- 0.0;
        coherent_stops <- 0;
        valid_stops <- 0;
        invalid_stops <- 0;
        problematic_stops <- [];
        invalid_stops_list <- [];
        min_distance_to_shape <- 999999.0;
        max_distance_to_shape <- 0.0;
        
        ask bus_stop {
            float min_dist_to_matching_shape <- 999999.0;
            transport_shape closest_matching_shape <- nil;
            bool found_valid_match <- false;
            list<transport_shape> matching_shapes <- [];
            
            // ✅ LOGIQUE CORRIGÉE: CHERCHER UNIQUEMENT LES SHAPES DU MÊME ROUTETYPE
            ask transport_shape {
                if shape != nil and myself.routeType != nil and routeType != nil {
                    // 🎯 CONDITION STRICTE: Même routeType obligatoire
                    if myself.routeType = routeType {
                        matching_shapes <- matching_shapes + self;
                        float dist <- myself.location distance_to shape;
                        
                        if dist < min_dist_to_matching_shape {
                            min_dist_to_matching_shape <- dist;
                            closest_matching_shape <- self;
                            found_valid_match <- true;
                        }
                    }
                }
            }
            
            // ✅ TRAITEMENT DES RÉSULTATS
            if found_valid_match {
                // CAS VALIDE: Correspondance trouvée avec le même routeType
                distance_to_closest_shape <- min_dist_to_matching_shape;
                closest_shape <- closest_matching_shape;
                has_matching_routetype <- true;
                match_strategy <- "RouteType Strict";
                is_valid_assignment <- true;
                myself.valid_stops <- myself.valid_stops + 1;
                
                // Statistiques globales (seulement pour les arrêts valides)
                myself.total_distance_sum <- myself.total_distance_sum + min_dist_to_matching_shape;
                if min_dist_to_matching_shape < myself.min_distance_to_shape {
                    myself.min_distance_to_shape <- min_dist_to_matching_shape;
                }
                if min_dist_to_matching_shape > myself.max_distance_to_shape {
                    myself.max_distance_to_shape <- min_dist_to_matching_shape;
                }
                
                // Test de cohérence spatiale
                if min_dist_to_matching_shape <= coherence_tolerance {
                    myself.coherent_stops <- myself.coherent_stops + 1;
                    is_coherent <- true;
                    color <- type_color; // Couleur selon le type de transport
                    
                    if cycle = 1 {
                        write "✅ Arrêt valide : " + display_name + 
                              " (" + type_name + ", distance: " + string(int(min_dist_to_matching_shape)) + "m)";
                    }
                } else {
                    is_coherent <- false;
                    myself.problematic_stops <- myself.problematic_stops + self;
                    color <- #orange; // Arrêts trop éloignés en orange
                    
                    write "⚠️  Arrêt éloigné : " + display_name + 
                          " (" + type_name + ", distance: " + string(int(min_dist_to_matching_shape)) + "m)";
                }
                
            } else {
                // ❌ CAS INVALIDE: Aucune correspondance avec le même routeType
                distance_to_closest_shape <- -1.0; // Valeur spéciale pour "non assigné"
                closest_shape <- nil;
                has_matching_routetype <- false;
                match_strategy <- "AUCUNE";
                is_valid_assignment <- false;
                is_coherent <- false;
                color <- #red; // Arrêts sans correspondance en rouge
                
                myself.invalid_stops <- myself.invalid_stops + 1;
                myself.invalid_stops_list <- myself.invalid_stops_list + self;
                
                // Diagnostic détaillé
                string available_types <- "";
                ask transport_shape {
                    if routeType != nil and not(contains(available_types, string(routeType))) {
                        string shape_type_name <- world.routetype_names contains_key routeType ? 
                                                  world.routetype_names[routeType] : string(routeType);
                        available_types <- available_types + shape_type_name + "(" + string(routeType) + ") ";
                    }
                }
                
                string my_type_name <- world.routetype_names contains_key routeType ? 
                                       world.routetype_names[routeType] : string(routeType);
                
                write "🚨 ARRÊT INVALIDE : " + display_name + 
                      " (Type: " + my_type_name + "(" + string(routeType) + "), Shapes disponibles: " + available_types + ")";
            }
        }
        
        // ✅ CALCUL DES STATISTIQUES (SEULEMENT SUR LES ARRÊTS VALIDES)
        if valid_stops > 0 {
            avg_distance_to_shape <- total_distance_sum / valid_stops;
        } else {
            avg_distance_to_shape <- 0.0;
        }
        
        // === AFFICHAGE DES RÉSULTATS CORRIGÉS ===
        write "";
        write "📊 RÉSULTATS DE L'ANALYSE (ROUTETYPE STRICT) :";
        write "   🚏 Arrêts analysés : " + string(total_stops);
        write "   📐 Shapes analysées : " + string(total_shapes);
        write "   ✅ Arrêts valides (avec correspondance RouteType) : " + string(valid_stops) + " (" + 
              string(total_stops > 0 ? int((valid_stops / total_stops) * 100) : 0) + "%)";
        write "   ❌ Arrêts invalides (sans correspondance RouteType) : " + string(invalid_stops);
        write "   ✅ Arrêts cohérents (valides + proches) : " + string(coherent_stops) + " (" + 
              string(valid_stops > 0 ? int((coherent_stops / valid_stops) * 100) : 0) + "% des valides)";
        write "   ⚠️  Arrêts éloignés (valides mais > " + coherence_tolerance + "m) : " + string(length(problematic_stops));
        write "";
        
        if valid_stops > 0 {
            write "📏 DISTANCES (ARRÊTS VALIDES UNIQUEMENT) :";
            write "   🎯 Distance minimale : " + string(int(min_distance_to_shape)) + " mètres";
            write "   📊 Distance moyenne : " + string(int(avg_distance_to_shape)) + " mètres";
            write "   📈 Distance maximale : " + string(int(max_distance_to_shape)) + " mètres";
            write "";
        }
        
        // === ANALYSE PAR ROUTETYPE ===
        write "📋 ANALYSE PAR TYPE DE TRANSPORT :";
        loop rt over: routetype_stats.keys {
            string type_name_analysis <- routetype_names contains_key rt ? routetype_names[rt] : ("Type_" + string(rt));
            list<bus_stop> stops_of_type <- bus_stop where (each.routeType = rt);
            list<bus_stop> valid_of_type <- stops_of_type where each.is_valid_assignment;
            list<bus_stop> coherent_of_type <- valid_of_type where each.is_coherent;
            
            int total_type <- length(stops_of_type);
            int valid_type <- length(valid_of_type);
            int coherent_type <- length(coherent_of_type);
            int shapes_type <- shape_routetype_stats contains_key rt ? shape_routetype_stats[rt] : 0;
            
            write "   " + type_name_analysis + " (" + string(rt) + ") : " + 
                  string(coherent_type) + "/" + string(valid_type) + "/" + string(total_type) + 
                  " (cohérents/valides/total) | " + string(shapes_type) + " shapes";
        }
        
        // === ÉVALUATION GLOBALE CORRIGÉE ===
        float data_quality_rate <- total_stops > 0 ? (valid_stops / total_stops) * 100 : 0;
        float spatial_coherence_rate <- valid_stops > 0 ? (coherent_stops / valid_stops) * 100 : 0;
        
        write "";
        write "🎯 ÉVALUATION GLOBALE :";
        write "🔍 QUALITÉ DES DONNÉES :";
        if data_quality_rate >= 95 {
            write "   🎉 EXCELLENTE : " + string(int(data_quality_rate)) + "% d'arrêts avec correspondance RouteType";
        } else if data_quality_rate >= 80 {
            write "   ✅ BONNE : " + string(int(data_quality_rate)) + "% d'arrêts avec correspondance RouteType";
        } else if data_quality_rate >= 60 {
            write "   ⚠️  MOYENNE : " + string(int(data_quality_rate)) + "% d'arrêts avec correspondance RouteType";
        } else {
            write "   ❌ PROBLÉMATIQUE : " + string(int(data_quality_rate)) + "% d'arrêts avec correspondance RouteType";
        }
        
        if valid_stops > 0 {
            write "🔍 COHÉRENCE SPATIALE (sur arrêts valides) :";
            if spatial_coherence_rate >= 90 {
                write "   🎉 EXCELLENTE : " + string(int(spatial_coherence_rate)) + "% de cohérence spatiale";
            } else if spatial_coherence_rate >= 70 {
                write "   ✅ BONNE : " + string(int(spatial_coherence_rate)) + "% de cohérence spatiale";
            } else if spatial_coherence_rate >= 50 {
                write "   ⚠️  MOYENNE : " + string(int(spatial_coherence_rate)) + "% de cohérence spatiale";
            } else {
                write "   ❌ PROBLÉMATIQUE : " + string(int(spatial_coherence_rate)) + "% de cohérence spatiale";
            }
        }
        
        // === RECOMMANDATIONS ===
        write "";
        write "🔍 RECOMMANDATIONS :";
        if invalid_stops > 0 {
            write "   📋 Nettoyer les données GTFS : " + string(invalid_stops) + " arrêts sans shapes correspondantes";
        }
        if avg_distance_to_shape > coherence_tolerance and valid_stops > 0 {
            write "   📐 Vérifier la projection géographique ou la précision des coordonnées";
        }
        if data_quality_rate < 90 {
            write "   🔧 Compléter les données GTFS avec les shapes manquantes pour les types requis";
        }
        if spatial_coherence_rate < 80 and valid_stops > 0 {
            write "   🎯 Améliorer la précision géographique des arrêts ou des tracés";
        }
        
        write "=== FIN DE L'ANALYSE ===";
    }
    
    // === MONITORING CONTINU ===
    reflex show_stats when: cycle mod 10 = 0 and cycle > 1 {
        float data_quality <- total_stops > 0 ? (valid_stops / total_stops) * 100 : 0;
        float spatial_quality <- valid_stops > 0 ? (coherent_stops / valid_stops) * 100 : 0;
        
        write "📊 Stats (Cycle " + string(cycle) + ") - Qualité données: " + string(int(data_quality)) + 
              "% | Cohérence spatiale: " + string(int(spatial_quality)) + 
              "% | Invalides: " + string(invalid_stops);
    }
}

// === SPECIES ARRÊT DE TRANSPORT (CORRIGÉ) ===
species bus_stop skills: [TransportStopSkill] {
    rgb color <- #blue;
    rgb type_color <- #blue;
    float size <- 100.0;
    string display_name;
    string type_name <- "Inconnu";
    bool is_important <- false;
    bool is_coherent <- false;
    bool has_matching_routetype <- false;
    bool is_valid_assignment <- false; // NOUVEAU: Indique si l'assignation est valide
    float distance_to_closest_shape <- 0.0;
    string match_strategy <- "";
    transport_shape closest_shape;
    
    action customInit {
        if stopName != nil and stopName != "" {
            display_name <- stopName;
        } else if stopId != nil {
            display_name <- "Arrêt_" + stopId;
        } else {
            display_name <- "Arrêt_" + string(self);
        }
    }
    
    aspect base {
        if location != nil {
            draw circle(size) at: location color: color border: #black;
        }
    }
    
    aspect detailed {
        if location != nil {
            draw circle(size) at: location color: color border: #black;
            if display_name != nil {
                draw display_name color: #black font: font("Arial", 10, #bold) 
                     at: location + {0, size + 15};
            }
        }
    }
    
    aspect coherence_analysis_strict {
        if location != nil {
            // ✅ AFFICHAGE SELON LA VALIDITÉ DE L'ASSIGNATION
            float display_size;
            rgb display_color;
            rgb border_color;
            float border_width;
            
            if is_valid_assignment {
                // Arrêt avec correspondance RouteType valide
                display_size <- is_coherent ? size : size * 1.2;
                display_color <- is_coherent ? type_color : #orange;
                border_color <- #black;
                border_width <- 1.0;
            } else {
                // ❌ Arrêt sans correspondance RouteType
                display_size <- size * 1.5;
                display_color <- #red;
                border_color <- #darkred;
                border_width <- 3.0;
            }
            
            draw circle(display_size) at: location color: display_color 
                 border: border_color width: border_width;
            
            if display_name != nil {
                rgb text_color;
                if is_valid_assignment {
                    text_color <- is_coherent ? #darkgreen : #darkorange;
                } else {
                    text_color <- #red;
                }
                
                draw display_name color: text_color font: font("Arial", 9, #bold) 
                     at: location + {0, display_size + 15};
                
                // Afficher le type de transport
                draw type_name color: type_color font: font("Arial", 8) 
                     at: location + {0, display_size + 30};
                
                // Informations de diagnostic
                if is_valid_assignment {
                    if not is_coherent {
                        string info_text <- string(int(distance_to_closest_shape)) + "m (éloigné)";
                        draw info_text color: #darkorange font: font("Arial", 8) 
                             at: location + {0, display_size + 45};
                    } else {
                        string info_text <- string(int(distance_to_closest_shape)) + "m ✓";
                        draw info_text color: #darkgreen font: font("Arial", 8) 
                             at: location + {0, display_size + 45};
                    }
                } else {
                    draw "SANS CORRESPONDANCE" color: #red font: font("Arial", 8, #bold) 
                         at: location + {0, display_size + 45};
                }
            }
        }
    }
}

// === SPECIES FORME DE TRANSPORT ===
species transport_shape skills: [TransportShapeSkill] {
    rgb line_color <- #blue;
    float line_width <- 3.0;
    
    action customInit {
        // Custom initialization if needed
    }
    
    aspect base {
        if shape != nil {
            draw shape color: line_color width: line_width;
        }
    }
    
    aspect detailed {
        if shape != nil {
            draw shape color: line_color width: line_width;
            
            // Afficher l'ID de la shape si disponible
            if shapeId != nil and shape != nil {
                point shape_center <- centroid(shape);
                string shape_info <- "Shape: " + shapeId;
                if routeType != nil {
                    string type_name_shape <- "(" + string(routeType) + ")";
                    shape_info <- shape_info + " " + type_name_shape;
                }
                draw shape_info color: line_color font: font("Arial", 8) 
                     at: shape_center;
            }
        }
    }
    
    aspect by_routetype {
        if shape != nil {
            // Épaisseur selon le type
            float width <- routeType != nil ? 
                (routeType = 1 ? 5.0 : (routeType = 0 ? 4.0 : 3.0)) : 2.0;
            
            draw shape color: line_color width: width;
        }
    }
}

// === EXPÉRIENCE DE VISUALISATION (AMÉLIORÉE) ===
experiment ShapeStopCoherenceTest_Strict type: gui {
    parameter "Projection CRS" var: projection_crs among: ["EPSG:3857", "EPSG:2154", "EPSG:4326"] 
              category: "Projection";
    parameter "Tolérance de cohérence (m)" var: coherence_tolerance min: 10.0 max: 500.0 
              category: "Analyse";
    
    output {
        // === DISPLAY UNIQUE : ANALYSE COMPLÈTE ===
        display "Analyse de Cohérence GTFS - RouteType Strict" type: 2d {
            // Fond avec les limites administratives
            graphics "Boundary" {
                if boundary_shp != nil {
                    draw boundary_shp color: #lightgray border: #black ;
                }
            }
            
            // Shapes de transport (dessiner en premier, en arrière-plan)
            species transport_shape aspect: by_routetype transparency: 0.6;
            
            // Arrêts de transport (dessiner par-dessus)
            species bus_stop aspect: coherence_analysis_strict;
            
            // === PANEL UNIQUE SIMPLIFIÉ ===
            overlay position: {10, 10} size: {400 #px, 350 #px} 
                     background: #white transparency: 0.9 {
                draw "=== ANALYSE DE COHÉRENCE GTFS (ROUTETYPE STRICT) ===" at: {5#px, 15#px} 
                     color: #black font: font("Arial", 12, #bold);
                
                // === INFORMATIONS GÉNÉRALES ===
                draw ("📍 Projection : " + projection_crs + " | 🔧 Tolérance : " + string(coherence_tolerance) + "m") 
                     at: {5#px, 35#px} color: #blue font: font("Arial", 9);
                draw ("📊 Données : " + string(total_stops) + " arrêts | " + string(total_shapes) + " shapes") 
                     at: {5#px, 50#px} color: #black font: font("Arial", 9);
                
                // === RÉSULTATS ===
                draw "RÉSULTATS :" at: {5#px, 75#px} color: #black font: font("Arial", 10, #bold);
                draw ("✅ Valides : " + string(valid_stops) + " (" + 
                      string(total_stops > 0 ? int((valid_stops / total_stops) * 100) : 0) + "%)")
                     at: {5#px, 95#px} color: #darkgreen font: font("Arial", 10);
                draw ("✅ Cohérents : " + string(coherent_stops) + " (" + 
                      string(valid_stops > 0 ? int((coherent_stops / valid_stops) * 100) : 0) + "% des valides)")
                     at: {5#px, 115#px} color: #green font: font("Arial", 10);
                draw ("⚠️  Éloignés : " + string(length(problematic_stops)) + " (valides mais > " + string(coherence_tolerance) + "m)") 
                     at: {5#px, 135#px} color: #orange font: font("Arial", 10);
                draw ("❌ Invalides : " + string(invalid_stops) + " (sans correspondance RouteType)") 
                     at: {5#px, 155#px} color: #red font: font("Arial", 10);
                
                // === DISTANCES ===
                if valid_stops > 0 {
                    draw "DISTANCES :" at: {5#px, 180#px} color: #black font: font("Arial", 10, #bold);
                    draw ("📏 Moyenne : " + string(int(avg_distance_to_shape)) + "m | Min : " + 
                          string(int(min_distance_to_shape)) + "m | Max : " + string(int(max_distance_to_shape)) + "m") 
                         at: {5#px, 200#px} color: #darkblue font: font("Arial", 9);
                }
                
                // === LÉGENDE ===
                draw "LÉGENDE :" at: {5#px, 225#px} color: #black font: font("Arial", 10, #bold);
                draw "🔵 Tram  🟠 Métro  🔴 Train  🟢 Bus  🟣 Autres" at: {5#px, 245#px} 
                     color: #black font: font("Arial", 9);
                draw "🔴 Rouge = Arrêt sans correspondance RouteType" at: {5#px, 260#px} 
                     color: #red font: font("Arial", 8);
                draw "🟠 Orange = Arrêt valide mais éloigné" at: {5#px, 275#px} 
                     color: #orange font: font("Arial", 8);
                draw "🟢 Couleur type = Arrêt valide et proche" at: {5#px, 290#px} 
                     color: #green font: font("Arial", 8);
                
                // === ÉVALUATION GLOBALE ===
                float quality_score <- 0.0;
                if total_stops > 0 {
                    float validity_rate <- (valid_stops / total_stops) * 100;
                    float coherence_rate <- valid_stops > 0 ? (coherent_stops / valid_stops) * 100 : 0;
                    quality_score <- (validity_rate * 0.4) + (coherence_rate * 0.6);
                }
                string quality_text <- "";
                rgb quality_color <- #black;
                if quality_score >= 95 {
                    quality_text <- "🎉 EXCELLENT (" + string(int(quality_score)) + "/100)";
                    quality_color <- #darkgreen;
                } else if quality_score >= 85 {
                    quality_text <- "✅ BON (" + string(int(quality_score)) + "/100)";
                    quality_color <- #green;
                } else if quality_score >= 70 {
                    quality_text <- "⚠️  MOYEN (" + string(int(quality_score)) + "/100)";
                    quality_color <- #orange;
                } else {
                    quality_text <- "❌ FAIBLE (" + string(int(quality_score)) + "/100)";
                    quality_color <- #red;
                }
                draw ("🎯 QUALITÉ GLOBALE : " + quality_text) at: {5#px, 315#px} 
                     color: quality_color font: font("Arial", 10, #bold);
                
                draw "Mode : CORRESPONDANCE STRICTE (pas de fallback)" at: {5#px, 335#px} 
                     color: #purple font: font("Arial", 8, #bold);
            }
        }
        
        // === MONITORS SIMPLIFIÉS ===
        monitor "🚏 Arrêts totaux" value: total_stops;
        monitor "📐 Shapes totales" value: total_shapes;
        monitor "✅ Valides (%)" value: total_stops > 0 ? int((valid_stops / total_stops) * 100) : 0;
        monitor "✅ Cohérents (%)" value: valid_stops > 0 ? int((coherent_stops / valid_stops) * 100) : 0;
        monitor "❌ Invalides" value: invalid_stops;
        monitor "📏 Distance moy (m)" value: int(avg_distance_to_shape);
        monitor "🔧 Tolérance (m)" value: coherence_tolerance;
        monitor "🔄 Cycle" value: cycle;
    }
    
    // === ACTIONS UTILISATEUR ===
    action focus_on_invalid {
        if length(invalid_stops_list) > 0 {
            ask invalid_stops_list {
                write "🔍 Arrêt invalide détecté : " + display_name + 
                      " (Type: " + type_name + ", Coord: " + location + ")";
            }
        } else {
            write "✅ Aucun arrêt invalide trouvé !";
        }
    }
    
    action focus_on_problematic {
        if length(problematic_stops) > 0 {
            ask problematic_stops {
                write "⚠️  Arrêt problématique : " + display_name + 
                      " (Distance: " + string(int(distance_to_closest_shape)) + "m)";
            }
        } else {
            write "✅ Aucun arrêt problématique trouvé !";
        }
    }
    
    action export_statistics {
        string export_text <- "=== RAPPORT D'ANALYSE GTFS ===\n";
        export_text <- export_text + "Date: " + string(current_date) + "\n";
        export_text <- export_text + "Projection: " + projection_crs + "\n";
        export_text <- export_text + "Tolérance: " + string(coherence_tolerance) + "m\n\n";
        
        export_text <- export_text + "DONNÉES:\n";
        export_text <- export_text + "- Arrêts totaux: " + string(total_stops) + "\n";
        export_text <- export_text + "- Shapes totales: " + string(total_shapes) + "\n\n";
        
        export_text <- export_text + "VALIDITÉ:\n";
        export_text <- export_text + "- Arrêts valides: " + string(valid_stops) + " (" + 
                       string(total_stops > 0 ? int((valid_stops / total_stops) * 100) : 0) + "%)\n";
        export_text <- export_text + "- Arrêts invalides: " + string(invalid_stops) + "\n\n";
        
        export_text <- export_text + "COHÉRENCE SPATIALE:\n";
        export_text <- export_text + "- Arrêts cohérents: " + string(coherent_stops) + " (" + 
                       string(valid_stops > 0 ? int((coherent_stops / valid_stops) * 100) : 0) + "%)\n";
        export_text <- export_text + "- Distance moyenne: " + string(int(avg_distance_to_shape)) + "m\n\n";
        
        export_text <- export_text + "DÉTAILS PAR TYPE:\n";
        loop rt over: routetype_stats.keys {
            string type_name_export <- routetype_names contains_key rt ? routetype_names[rt] : ("Type_" + string(rt));
            list<bus_stop> stops_of_type <- bus_stop where (each.routeType = rt);
            list<bus_stop> valid_of_type <- stops_of_type where each.is_valid_assignment;
            list<bus_stop> coherent_of_type <- valid_of_type where each.is_coherent;
            
            export_text <- export_text + "- " + type_name_export + ": " + 
                          string(length(coherent_of_type)) + "/" + 
                          string(length(valid_of_type)) + "/" + 
                          string(length(stops_of_type)) + " (cohérents/valides/total)\n";
        }
        
        write "📄 Rapport exporté dans la console";
        write export_text;
    }
}