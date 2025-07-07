model testDepartureStopsInfor

global {
// Path to the GTFS file
gtfs_file gtfs_f <- gtfs_file("../../includes/tisseo_gtfs_v2");

shape_file boundary_shp <- shape_file("../../includes/shapeFileToulouse.shp");

geometry shape <- envelope(boundary_shp);

date starting_date <- date("2025-06-10T16:00:00"); 

// Variables pour stocker les statistiques
int nombre_stops_avec_departs <- 0;
int nombre_total_trips <- 0;
int nombre_total_agent_stops <- 0;

// Initialization section
init {

// Create bus_stop agents from the GTFS data
create bus_stop from: gtfs_f {

}

ask bus_stop{ do customInit;}

// Calculer et afficher les statistiques après l'initialisation
do calculer_statistiques;

}

// Action pour calculer les statistiques
action calculer_statistiques {
    nombre_stops_avec_departs <- 0;
    nombre_total_trips <- 0;
    nombre_total_agent_stops <- 0;
    
    // Parcourir tous les bus_stop
    ask bus_stop {
        // Vérifier si departureStopsInfo n'est pas null et non vide
        if departureStopsInfo != nil and length(departureStopsInfo) > 0 {
            myself.nombre_stops_avec_departs <- myself.nombre_stops_avec_departs + 1;
            
            // Parcourir chaque tripId dans departureStopsInfo
            loop tripId over: departureStopsInfo.keys {
                myself.nombre_total_trips <- myself.nombre_total_trips + 1;
                
                // Compter le nombre de paires (agent stops) pour ce trip
                list paires <- departureStopsInfo[tripId];
                if paires != nil {
                    myself.nombre_total_agent_stops <- myself.nombre_total_agent_stops + length(paires);
                }
            }
        }
    }
    
    // Afficher les résultats
    write "=== STATISTIQUES DEPARTURESTOPSINFO ===";
    write "1. Nombre de stops de départ (avec departureStopsInfo non null): " + nombre_stops_avec_departs;
    write "2. Nombre total de trips dans tous les departureStopsInfo: " + nombre_total_trips;
    write "3. Nombre total d'agent stops (paires stopID-heure): " + nombre_total_agent_stops;
    write "=========================================";
}

}

// Species representing each transport stop
species bus_stop skills: [TransportStopSkill] {

action customInit {
    if departureStopsInfo != nil and length(departureStopsInfo) > 0 {
        write "Bus stop " + stopId + " (" + stopName + ") initialisé avec " + length(departureStopsInfo) + " trips";
        
        // Optionnel: afficher le détail pour chaque stop
        loop tripId over: departureStopsInfo.keys {
            list paires <- departureStopsInfo[tripId];
            write "  - Trip " + tripId + ": " + length(paires) + " agent stops";
        }
    }
}

aspect base {
    // Colorer différemment les stops avec/sans départs
    rgb couleur <- (#gray);
    if departureStopsInfo != nil and length(departureStopsInfo) > 0 {
        couleur <- #blue;
    }
    
    draw circle (100.0) at: location color: couleur;
}
}

species my_species skills: [TransportStopSkill] {
// Accès à la liste des arrêts créés
reflex check_stops {
    //write "Nombre d'arrêts créés: " + length(bus_stop); // Affiche le nombre d'arrêts créés
}
aspect base {
    draw circle (100.0) at: location color:#blue;
}
}

// GUI-based experiment for visualization
experiment GTFSExperiment type: gui {

// Output section to define the display
output {
    // Display the bus stops on the map
    display "Bus Stops And Envelope" {
        // Draw boundary envelope
        
        // Display the bus_stop agents on the map
        species bus_stop aspect: base;
        species my_species aspect:base;
    }
    
    // Nouveau display pour afficher les statistiques
    display "Statistiques" type: java2D {
        chart "Statistiques departureStopsInfo" type: histogram background: #white {
            data "Stops avec départs" value: nombre_stops_avec_departs color: #blue;
            data "Total trips" value: nombre_total_trips color: #green;
            data "Total agent stops" value: nombre_total_agent_stops color: #red;
        }
    }
}
}