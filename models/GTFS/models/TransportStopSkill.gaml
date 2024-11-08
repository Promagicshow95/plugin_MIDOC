model TransportStopKill

global {
    // Chemin vers le dossier contenant les fichiers GTFS
    string gtfs_file_path <- "C:\\Users\\tiend\\Desktop\\Prepared for MIDOC\\Prepared for MIDOC\\Donnée\\DataFile\\tisseo_gtfs_v2";

    
    init {
        write "Chargement des données GTFS à partir de : " + gtfs_file_path;
        
        // Create transport stop agents from GTFS data
        create TransportStop from: gtfs_file_path;
        
        // Display attributes of each created agent
        ask TransportStop {
            write "Transport Stop ID: " + self.stopId;
            write "Stop Name: " + self.stopName;
            
       
				
        }
}

}

species TransportStop skills: [TransportStopSkill] {
    // Définition des attributs comme dans TransportStopSkill pour être affichés dans GAML
    string stopId;
    string stopName;
    
    aspect default {
        draw shape color: #blue;
    }
}

experiment DisplayGTFSStops type: gui {
    output {
        display displayView {
            species TransportStop aspect: default;
        }
    }
}

