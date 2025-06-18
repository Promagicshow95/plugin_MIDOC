model FilterGTFS

global skills: [gtfs_filter] {
    string gtfs_path <- "../../includes/hanoi_gtfs_pm";
    string osm_path <- "../../includes/Hanoi_map.osm";
    string output_path <- "../../includes/filtered_gtfs";

    init {
        do filter_gtfs_with_osm;
    }
}

experiment demo type: gui {}
