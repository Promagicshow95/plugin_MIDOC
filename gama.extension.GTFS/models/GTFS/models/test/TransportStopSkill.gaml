model GTFSreader

global {
    // Path to the GTFS file
    gtfs_file gtfs_f <- gtfs_file("../../includes/tisseo_gtfs_v2");
	shape_file boundary_shp <- shape_file("../../includes/boundaryTLSE-WGS84PM.shp");
	shape_file cleaned_road_shp <- shape_file("../../includes/cleaned_network.shp");
	geometry shape <- envelope(boundary_shp);

    // Initialization section
    init {     
        // Create bus_stop agents from the GTFS data
       create bus_stop from: gtfs_f  {
    
      

				
       }
       
       
       
       
//       list<bus_stop> busStopList <- list<bus_stop>(bus_stop);
//        list<bus_stop> busStopsToBeDeleted <- [];
//
//        loop _busStop_1 over:  busStopList {
//              loop _busStop_2 over: busStopList{
//                if( _busStop_1.stopId = _busStop_2.stopId) and not ((busStopsToBeDeleted collect each.stopId )  contains  _busStop_1.stopId){
//                    add  _busStop_2  to:  busStopsToBeDeleted ;
//                  }
//            }
//        }
//
//
//
//        ask busStopsToBeDeleted { do die;}
//       
//       
       
    }
    
}

// Species representing each transport stop
species bus_stop skills: [TransportStopSkill] {
	
	
  action customInit  {
    	if length(departureStopsInfo)> 0 {
       
       }

		
    }
    // Attributes for latitude and longitude
//    float latitude <- 0.0;
//    float longitude <- 0.0;
//		--> in the location attribute

//    string stopId <- "";
//    string stopName <- "";
//		--> built-in attributes from the skill



    // Initialization of the stop's attributes
//    init {
//        latitude <- attribute("latitude");
//        longitude <- attribute("longitude");
//        stopId <- attribute("stopId");
//        stopName <- attribute("stopName");
//    }
    
     aspect base {
     	
     	
		draw circle (100.0) at: location color:#blue;	
     }
}

species my_species skills: [TransportStopSkill] {
    // Accès à la liste des arrêts créés
    reflex check_stops {
        write "Nombre d'arrêts créés: " + length(bus_stop);  // Affiche le nombre d'arrêts créés
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
    }
}
