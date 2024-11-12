/**
* Name: TransportStopSkillNonDelegate
* Based on the internal empty template. 
* Author: tiend
* Tags: 
*/


model TransportStopSkillNonDelegate

global {
    // Chemin vers le dossier contenant les fichiers GTFS
    string gtfs_file_path <- "C:\\Users\\tiend\\Desktop\\Prepared for MIDOC\\Prepared for MIDOC\\Donnée\\DataFile\\tisseo_gtfs_v2";

    init {
        write "Chargement des données GTFS à partir de : " + gtfs_file_path;
        
        // Création d'un seul agent pour charger les arrêts
        create bus_stop number: 1 {
            do loadStopsFromGTFS filePath: gtfs_file_path;
        }
    }
}

// Définition de l'espèce `bus_stop` avec le skill `TransportStopSkill`
species bus_stop skills: [TransportStopSkillNonDelegate] {
    
    // Attributs spécifiques à chaque arrêt de bus
    string stopId;
    string stopName;

    // Aspect pour afficher chaque arrêt de transport
    aspect base {
        draw circle(5) color: #blue; 
    }
}

// Expérience GUI pour la visualisation des arrêts
experiment GTFSExperiment type: gui {
    
    // Affichage de la carte avec les arrêts de transport
    output {
        display "Carte des Arrêts de Transport" {
            species bus_stop aspect: base;
        }
    }
}
