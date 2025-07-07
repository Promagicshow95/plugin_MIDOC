model ShapeStopProjectionTest

global {
    // === CONFIGURATION DE LA PROJECTION ===
    // Utilisation de Web Mercator comme dans votre exemple, ou Lambert-93 pour la France
    string projection_crs <- "EPSG:3857"; // Web Mercator
    // Alternative pour la France : "EPSG:2154" (Lambert-93)
    
    // === FICHIERS DE DONNÉES ===
    gtfs_file gtfs_f <- gtfs_file("../../includes/ToulouseFilter_gtfs_cleaned");
    shape_file boundary_shp <- shape_file("../../includes/ToulouseFilter_wgs84.shp");
    geometry shape <- envelope(boundary_shp);
    
    // === VARIABLES DE TEST ===
    int total_stops <- 0;
    int total_shapes <- 0;
    float coherence_tolerance <- 100.0; // Distance en mètres pour considérer qu'un stop est "sur" une shape
    int coherent_stops <- 0;
    list<bus_stop> problematic_stops <- [];
    
    // === NOUVELLES VARIABLES POUR ROUTETYPE ===
    int stops_without_matching_routetype <- 0;
    map<int, int> routetype_stats <- []; // routeType -> nombre d'arrêts
    map<int, int> shape_routetype_stats <- []; // routeType -> nombre de shapes
    
    // === STATISTIQUES DE COHÉRENCE ===
    float min_distance_to_shape <- 999999.0;
    float max_distance_to_shape <- 0.0;
    float avg_distance_to_shape <- 0.0;
    float total_distance_sum <- 0.0;
    
    init {
        write "=== TEST DE COHÉRENCE SPATIALE SHAPE-STOP AVEC ROUTETYPE ===";
        write "📍 Projection utilisée : " + projection_crs;
        write "📏 Tolérance de cohérence : " + string(coherence_tolerance) + " mètres";
        write "";
        
        // Définir la projection avant de charger les données
        write "🔧 Configuration de la projection...";
        
        write "📂 Chargement des données GTFS depuis : tisseo_gtfs_v2";
        
        // === CRÉATION DES ARRÊTS ===
        write "🚏 Création des arrêts de bus...";
        create bus_stop from: gtfs_f {
            // Personnalisation de l'affichage
            if stopName != nil {
                display_name <- stopName;
                // Identifier les arrêts importants
                if contains(stopName, "Capitole") or contains(stopName, "Gare") {
                    color <- #red;
                    size <- 150.0;
                    is_important <- true;
                }
            } else {
                display_name <- "Arrêt_" + stopId;
            }
            
            // NOUVEAU: Couleur selon le routeType
            if routeType != nil {
                switch routeType {
                    match 0 { type_color <- #blue; type_name <- "Tram"; }      // Tram
                    match 1 { type_color <- #orange; type_name <- "Métro"; }   // Métro  
                    match 2 { type_color <- #red; type_name <- "Train"; }      // Train
                    match 3 { type_color <- #green; type_name <- "Bus"; }      // Bus
                    match 4 { type_color <- #cyan; type_name <- "Ferry"; }     // Ferry
                    match 5 { type_color <- #magenta; type_name <- "Câble"; }  // Câble
                    match 6 { type_color <- #yellow; type_name <- "Gondole"; } // Gondole
                    match 7 { type_color <- #purple; type_name <- "Funiculaire"; } // Funiculaire
                    default { type_color <- #gray; type_name <- "Autre"; }
                }
            } else {
                type_color <- #gray;
                type_name <- "Inconnu";
            }
        }
        
        // Compter APRÈS la création
        total_stops <- length(bus_stop);
        write "✅ " + string(total_stops) + " arrêts créés";
        
        // === CRÉATION DES SHAPES ===
        write "📐 Création des formes de transport...";
        create transport_shape from: gtfs_f {
            // NOUVEAU: Récupération du routeType depuis les routes GTFS
            // Note: En GTFS, les shapes sont liées aux trips, qui sont liés aux routes
            // Il faut donc récupérer le routeType via cette relation
            
            // Couleur selon le routeType (si disponible)
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
        
        write "📊 Statistiques des RouteTypes:";
        loop rt over: routetype_stats.keys {
            string type_name <- "";
            switch rt {
                match 0 { type_name <- "Tram"; }
                match 1 { type_name <- "Métro"; }
                match 2 { type_name <- "Train"; }
                match 3 { type_name <- "Bus"; }
                default { type_name <- "Autre (" + rt + ")"; }
            }
            int stop_count <- routetype_stats[rt];
            int shape_count <- shape_routetype_stats contains_key rt ? shape_routetype_stats[rt] : 0;
            write "   " + type_name + ": " + stop_count + " arrêts, " + shape_count + " shapes";
        }
        
        write "🚀 Modèle initialisé - Analyse de cohérence en cours...";
    }
    
    // === ANALYSE DE COHÉRENCE SPATIALE AVEC ROUTETYPE ===
    reflex analyze_coherence when: cycle = 1 {
        write "=== ANALYSE DE COHÉRENCE SPATIALE (AVEC ROUTETYPE) ===";
        
        total_distance_sum <- 0.0;
        coherent_stops <- 0;
        problematic_stops <- [];
        stops_without_matching_routetype <- 0;
        min_distance_to_shape <- 999999.0;
        max_distance_to_shape <- 0.0;
        
        ask bus_stop {
            float min_dist_to_matching_shape <- 999999.0;
            float min_dist_to_any_shape <- 999999.0;
            transport_shape closest_matching_shape <- nil;
            transport_shape closest_any_shape <- nil;
            bool found_matching_routetype <- false;
            
            // NOUVEAU: Chercher d'abord les shapes avec le même routeType
            ask transport_shape {
                if shape != nil {
                    float dist <- myself.location distance_to shape;
                    
                    // Distance à n'importe quelle shape
                    if dist < min_dist_to_any_shape {
                        min_dist_to_any_shape <- dist;
                        closest_any_shape <- self;
                    }
                    
                    // Distance aux shapes du même routeType
                    if myself.routeType != nil and routeType != nil and myself.routeType = routeType {
                        found_matching_routetype <- true;
                        if dist < min_dist_to_matching_shape {
                            min_dist_to_matching_shape <- dist;
                            closest_matching_shape <- self;
                        }
                    }
                }
            }
            
            // LOGIQUE DE CHOIX: Priorité aux shapes du même routeType
            float chosen_distance;
            string match_type;
            
            if found_matching_routetype {
                chosen_distance <- min_dist_to_matching_shape;
                match_type <- "RouteType";
                closest_shape <- closest_matching_shape;
            } else {
                chosen_distance <- min_dist_to_any_shape;
                match_type <- "Toute";
                closest_shape <- closest_any_shape;
                myself.stops_without_matching_routetype <- myself.stops_without_matching_routetype + 1;
                
                write "⚠️  " + display_name + " (RouteType: " + routeType + 
                      ") - Aucune shape correspondante trouvée, utilisation de la plus proche";
            }
            
            // Enregistrer les résultats
            distance_to_closest_shape <- chosen_distance;
            has_matching_routetype <- found_matching_routetype;
            match_strategy <- match_type;
            
            // Statistiques globales
            myself.total_distance_sum <- myself.total_distance_sum + chosen_distance;
            if chosen_distance < myself.min_distance_to_shape {
                myself.min_distance_to_shape <- chosen_distance;
            }
            if chosen_distance > myself.max_distance_to_shape {
                myself.max_distance_to_shape <- chosen_distance;
            }
            
            // Test de cohérence
            if chosen_distance <= coherence_tolerance {
                myself.coherent_stops <- myself.coherent_stops + 1;
                is_coherent <- true;
                color <- found_matching_routetype ? type_color : #lightgreen;
            } else {
                is_coherent <- false;
                myself.problematic_stops <- myself.problematic_stops + self;
                color <- #orange; // Arrêts problématiques en orange
                write "❌ Arrêt incohérent : " + display_name + 
                      " (distance: " + string(int(chosen_distance)) + "m, match: " + match_type + ")";
            }
        }
        
        // Calcul de la moyenne
        avg_distance_to_shape <- total_distance_sum / total_stops;
        
        // === AFFICHAGE DES RÉSULTATS ===
        write "📊 RÉSULTATS DE L'ANALYSE (AVEC ROUTETYPE) :";
        write "   🚏 Arrêts analysés : " + string(total_stops);
        write "   📐 Shapes analysées : " + string(total_shapes);
        write "   ✅ Arrêts cohérents : " + string(coherent_stops) + " (" + 
              string(int((coherent_stops / total_stops) * 100)) + "%)";
        write "   ⚠️  Arrêts problématiques : " + string(length(problematic_stops));
        write "   🔄 Arrêts sans RouteType correspondant : " + string(stops_without_matching_routetype);
        write "";
        write "📏 DISTANCES :";
        write "   🎯 Distance minimale : " + string(int(min_distance_to_shape)) + " mètres";
        write "   📊 Distance moyenne : " + string(int(avg_distance_to_shape)) + " mètres";
        write "   📈 Distance maximale : " + string(int(max_distance_to_shape)) + " mètres";
        write "";
        
        // === ÉVALUATION GLOBALE ===
        float coherence_rate <- (coherent_stops / total_stops) * 100;
        float routetype_match_rate <- ((total_stops - stops_without_matching_routetype) / total_stops) * 100;
        
        write "🎯 TAUX DE CORRESPONDANCE ROUTETYPE : " + string(int(routetype_match_rate)) + "%";
        
        if coherence_rate >= 90 {
            write "🎉 EXCELLENT : Cohérence spatiale très bonne (" + string(int(coherence_rate)) + "%)";
        } else if coherence_rate >= 70 {
            write "✅ BON : Cohérence spatiale acceptable (" + string(int(coherence_rate)) + "%)";
        } else if coherence_rate >= 50 {
            write "⚠️  MOYEN : Cohérence spatiale à améliorer (" + string(int(coherence_rate)) + "%)";
        } else {
            write "❌ PROBLÈME : Cohérence spatiale insuffisante (" + string(int(coherence_rate)) + "%)";
        }
        
        if avg_distance_to_shape > coherence_tolerance {
            write "🔍 RECOMMANDATION : Vérifier la projection ou la qualité des données GTFS";
        }
        
        if routetype_match_rate < 80 {
            write "🔍 RECOMMANDATION : Vérifier la cohérence des RouteTypes entre arrêts et shapes";
        }
    }
    
    // === MONITORING CONTINU ===
    reflex show_stats when: cycle mod 10 = 0 and cycle > 1 {
        write "📊 Stats (Cycle " + string(cycle) + ") - Cohérents: " + string(coherent_stops) + "/" + string(total_stops) + 
              " (" + string(int((coherent_stops / total_stops) * 100)) + "%) | Sans RouteType: " + string(stops_without_matching_routetype);
    }
}

// === SPECIES ARRÊT DE BUS (AMÉLIORÉ) ===
species bus_stop skills: [TransportStopSkill] {
    rgb color <- #blue;
    rgb type_color <- #blue; // NOUVEAU: Couleur selon le routeType
    float size <- 100.0;
    string display_name;
    string type_name <- "Inconnu"; // NOUVEAU: Nom du type de transport
    bool is_important <- false;
    bool is_coherent <- false;
    bool has_matching_routetype <- false; // NOUVEAU: Indique si une shape du même routeType a été trouvée
    float distance_to_closest_shape <- 0.0;
    string match_strategy <- ""; // NOUVEAU: "RouteType" ou "Toute"
    transport_shape closest_shape; // NOUVEAU: Référence vers la shape la plus proche
    
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
    
    aspect coherence_analysis {
        if location != nil {
            // Taille selon la cohérence et correspondance RouteType
            float display_size <- is_coherent ? 
                (has_matching_routetype ? size : size * 0.8) : size * 1.5;
            
            // Couleur selon cohérence et correspondance RouteType
            rgb display_color;
            if is_coherent {
                display_color <- has_matching_routetype ? type_color : #lightgreen;
            } else {
                display_color <- #orange;
            }
            
            // Bordure selon la correspondance RouteType
            rgb border_color <- has_matching_routetype ? #black : #red;
            float border_width <- has_matching_routetype ? 1.0 : 3.0;
            
            draw circle(display_size) at: location color: display_color 
                 border: border_color width: border_width;
            
            if display_name != nil {
                rgb text_color <- is_coherent ? #darkgreen : #red;
                draw display_name color: text_color font: font("Arial", 9, #bold) 
                     at: location + {0, display_size + 15};
                
                // NOUVEAU: Afficher le type de transport
                draw type_name color: type_color font: font("Arial", 8) 
                     at: location + {0, display_size + 30};
            }
            
            // Afficher la distance et stratégie pour les arrêts problématiques
            if not is_coherent or not has_matching_routetype {
                string info_text <- string(int(distance_to_closest_shape)) + "m (" + match_strategy + ")";
                draw info_text color: #red font: font("Arial", 8) 
                     at: location + {0, display_size + 45};
            }
        }
    }
}

// === SPECIES FORME DE TRANSPORT (INCHANGÉ) ===
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
                draw ("Shape: " + shapeId) color: line_color font: font("Arial", 8) 
                     at: shape_center;
            }
        }
    }
}

// === EXPÉRIENCE DE VISUALISATION (AMÉLIORÉE) ===
experiment ShapeStopCoherenceTest type: gui {
    parameter "Projection CRS" var: projection_crs among: ["EPSG:3857", "EPSG:2154", "EPSG:4326"] 
              category: "Projection";
    parameter "Tolérance de cohérence (m)" var: coherence_tolerance min: 10.0 max: 500.0 
              category: "Analyse";
    
    output {
        // === DISPLAY PRINCIPAL : ANALYSE DE COHÉRENCE ===
        display "Test de Cohérence Shape-Stop (RouteType)" type: 2d {
            // Fond avec les limites administratives
            graphics "Boundary" {
                if boundary_shp != nil {
                    draw boundary_shp color: #lightgray border: #black ;
                }
            }
            
            // Shapes de transport (dessiner en premier, en arrière-plan)
            species transport_shape aspect: base transparency: 0.6;
            
            // Arrêts de bus (dessiner par-dessus)
            species bus_stop aspect: coherence_analysis;
            
            // Légende et informations
            overlay position: {10, 10} size: {400 #px, 240 #px} 
                     background: #white transparency: 0.9 {
                draw "=== TEST DE COHÉRENCE SHAPE-STOP (ROUTETYPE) ===" at: {5#px, 15#px} 
                     color: #black font: font("Arial", 11, #bold);
                draw ("Projection : " + projection_crs) at: {5#px, 35#px} color: #blue;
                draw ("Arrêts : " + string(total_stops) + " | Shapes : " + string(total_shapes)) at: {5#px, 55#px} color: #black;
                draw ("Cohérents : " + string(coherent_stops) + " (" + 
                      string(int((coherent_stops > 0 ? (coherent_stops / total_stops) * 100 : 0))) + "%)")
                     at: {5#px, 75#px} color: #green;
                draw ("Problématiques : " + string(length(problematic_stops))) at: {5#px, 95#px} color: #orange;
                draw ("Sans RouteType : " + string(stops_without_matching_routetype)) at: {5#px, 115#px} color: #red;
                draw ("Tolérance : " + string(coherence_tolerance) + "m") at: {5#px, 135#px} color: #purple;
                
                // Légende des couleurs et RouteTypes
                draw "🔵 Tram  🟠 Métro  🔴 Train  🟢 Bus" at: {5#px, 160#px} 
                     color: #black font: font("Arial", 9);
                draw "Bordure rouge = Pas de RouteType correspondant" at: {5#px, 180#px} 
                     color: #red font: font("Arial", 8);
                draw ("Distance moy : " + string(int(avg_distance_to_shape)) + "m") at: {5#px, 200#px} color: #darkblue;
            }
        }
        
        // === GRAPHIQUE : ANALYSE PAR ROUTETYPE ===
        display "Analyse par RouteType" {
            chart "Cohérence par Type de Transport" type: histogram {
                if total_stops > 0 {
                    loop rt over: routetype_stats.keys {
                        string type_name <- "";
                        switch rt {
                            match 0 { type_name <- "Tram"; }
                            match 1 { type_name <- "Métro"; }
                            match 2 { type_name <- "Train"; }
                            match 3 { type_name <- "Bus"; }
                            default { type_name <- "Autre"; }
                        }
                        
                        list<bus_stop> stops_of_type <- bus_stop where (each.routeType = rt);
                        int coherent_of_type <- length(stops_of_type where each.is_coherent);
                        int total_of_type <- length(stops_of_type);
                        
                        if total_of_type > 0 {
                            data type_name + " (" + coherent_of_type + "/" + total_of_type + ")" 
                                 value: (coherent_of_type / total_of_type) * 100;
                        }
                    }
                }
            }
        }
        
        // === MONITOR : CONSOLE DE DIAGNOSTIC (AMÉLIORÉ) ===
        monitor "Arrêts totaux" value: total_stops;
        monitor "Shapes totales" value: total_shapes;
        monitor "Arrêts cohérents" value: coherent_stops;
        monitor "Taux de cohérence (%)" value: total_stops > 0 ? int((coherent_stops / total_stops) * 100) : 0;
        monitor "Sans RouteType correspondant" value: stops_without_matching_routetype;
        monitor "Taux RouteType (%)" value: total_stops > 0 ? int(((total_stops - stops_without_matching_routetype) / total_stops) * 100) : 0;
        monitor "Distance moyenne (m)" value: int(avg_distance_to_shape);
        monitor "Distance max (m)" value: int(max_distance_to_shape);
    }
}