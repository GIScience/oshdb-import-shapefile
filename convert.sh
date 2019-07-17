#!/usr/bin/env bash

## INSTALL - MacOS
# git clone --recursive https://github.com/pnorman/ogr2osm

# brew install osmium-tool
# brew install osmfilter

# brew install maven
# git clone https://github.com/giscience/oshdb
# cd oshdb/oshdb-tool/etl && mvn package && cd ../../../

## INSTALL - Ubuntu

# git clone --recursive https://github.com/pnorman/ogr2osm
# sudo apt-get install -y python-gdal python-lxml

# sudo apt-get install -y osmctools osmium-tool

# sudo apt-get install -y maven default-jdk
# git clone https://github.com/giscience/oshdb
# cd oshdb/oshdb-tool/etl && mvn package && cd ../../../

## RUN

FILE=$PWD/[shapefile without extension]
ENCODING="UTF-8"
KEY_POINT="[key for a point]"
VALUE_POINT="[value for a point]"
KEY_POLYGON="[key for a polygon]"
VALUE_POLYGON="[value for a polygon]"
KEY_AREA="[key for an area]"
VALUE_AREA="[value for an area]"
ATTRIBUTION="[attribution]"
ATTRIBUTION2="[attribution]"
ATTRIBUTION_URL="[attribution url]"
CLEANUP=1

mkdir -p ./tmp

translation="""
from geom import *

POINT = 'POINT'
WAY = 'WAY'
AREA = 'AREA'

def filterTags(attrs):
  attrs['source'] = '$ATTRIBUTION2'
  return attrs

def preOutputTransform(geometries, features):
  for feature in features:
    print(feature)
    feature.tags['natural'] = 'water'
  if False:
    gt = geometryType(feature.geometry)
    if gt == POINT:
      feature.tags['$KEY_POINT'] = '$VALUE_POINT'
    elif gt == WAY:
      feature.tags['$KEY_POLYGON'] = '$VALUE_POLYGON'
    elif gt == AREA:
      feature.tags['$KEY_AREA'] = '$VALUE_AREA'
    print(feature.tags)

def geometryType(geometry):
  if type(geometry) == Point:
    return POINT
  elif type(geometry) == Way:
    try:
      return AREA if geometry.points[0] == geometry.points[-1] else WAY
    except:
      return WAY
  elif type(geometry) == Relation:
    return AREA if all(map(lambda m: geometryType(m[0]) == AREA, geometry.members)) else WAY
  return None
"""
echo "$translation" > ./tmp/translation.py

python ogr2osm/ogr2osm.py --no-memory-copy --encoding=$ENCODING --id=9000000000000000 --translation=./tmp/translation.py $FILE.shp --output=$FILE.osm

osmconvert $FILE.osm -o=$FILE.osh.pbf
osmium sort $FILE.osh.pbf -o $FILE.sorted.osh.pbf

# alternative:
# osmium sort $FILE.osm -o $FILE.sorted.osh.pbf

if [ -x "$(command -v md5)" ]; then
  md5=`md5 -q $FILE.sorted.osh.pbf`
else
  md5=`md5sum --tag $FILE.sorted.osh.pbf`
fi

time java -Xms64g -Xmx64g -server -XX:+UseG1GC -cp oshdb/oshdb-tool/etl/target/etl-0.5.0-SNAPSHOT.jar org.heigit.bigspatialdata.oshdb.tool.importer.extract.Extract --pbf $FILE.sorted.osh.pbf -tmpDir ./tmp -workDir ./tmp --md5 "$md5" --timevalidity_from 1900-01-01

time java -Xms64g -Xmx64g -server -XX:+UseG1GC -cp oshdb/oshdb-tool/etl/target/etl-0.5.0-SNAPSHOT.jar org.heigit.bigspatialdata.oshdb.tool.importer.transform.Transform --pbf $FILE.sorted.osh.pbf -tmpDir ./tmp -workDir ./tmp

cd oshdb/oshdb-tool/etl/
mvn exec:java -Dexec.mainClass="org.heigit.bigspatialdata.oshdb.tool.importer.load.handle.OSHDB2H2Handler" -Dexec.args="-tmpDir ./../../../tmp -workDir ./../../../tmp --out $FILE --attribution '(c) by $ATTRIBUTION' --attribution-url '$ATTRIBUTION_URL'"
cd ../../../

if [ "$CLEANUP" = "1" ]; then
  rm $FILE.osh.pbf
  rm $FILE.osm
  rm $FILE.sorted.osh.pbf
  rm $FILE.sorted.osh.pbf.meta
fi

rm -rf ./tmp
