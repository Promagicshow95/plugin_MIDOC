/**
* Name: NewModel
* Based on the internal empty template. 
* Author: tiend
* Tags: 
*/


model NewModel

global{
	shape_file boundary_shp <- shape_file("../../includes/boundaryTLSE-WGS84PM.shp");
	shape_file cleaned_road_shp <- shape_file("../../includes/cleaned_network.shp"); 
	gtfs_file gtfs_f <- gtfs_file("../../includes/tisseo_gtfs_v2");	
	geometry shape <- envelope(boundary_shp);
	graph road_network;
	
	init{
		
		create transport_shape from: gtfs_f {
         
        }
        
     	map<geometry, int> shape_to_routeType <- map(transport_shape collect (each.shape::each.routeType));
     	
		create road from: cleaned_road_shp{
      
        
        }
	
        
}

}

species road {
    aspect default {
        draw shape color: #black;
    }
    int routeType;
}

species transport_shape skills: [TransportShapeSkill] {

}

experiment GTFSExperiment type: gui {
    output {
        display "Bus Simulation" {

            species road aspect: default;
        }
    }
}

