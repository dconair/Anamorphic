# Wie ein Anamorphot arbeitet – und was die App daraus nachbaut

## Die echte Aufnahme (Squeeze → Sensor → Desqueeze)

1. **Squeeze.** Zylindrische Linsenelemente stauchen das Bild nur horizontal (typisch 1.33×, 1.5×, 1.8×, 2×).
   Die vertikale Brennweite bleibt, die horizontale ist um den Faktor kürzer: Ein 50-mm-2×-Anamorphot hat
   vertikal den Bildwinkel eines 50-mm-Objektivs, horizontal etwa den eines 25-mm-Objektivs
   ([PhotographyLife](https://photographylife.com/what-is-anamorphic-lens), [InDepthCine](https://www.indepthcine.com/videos/anamorphic-squeeze)).
   Der Sensor nimmt also **mehr Szene in der Breite** auf, nicht dasselbe Bild verzerrt.
2. **Optik im gestauchten Raum.** Unschärfe, Blendenform, Flares und Randabfall entstehen vor dem Sensor – in
   gestauchter Geometrie. Ein vertikaler Defokus-Radius ist deshalb länger als ein horizontaler.
3. **Desqueeze.** In der Postproduktion wird um denselben Faktor gestreckt (1.5× Linse → 1.5× Desqueeze;
   [ARRI Desqueeze White Paper](https://www.arri.com/resource/blob/186772/228c1a0523ed25947174567833cd8fb4/anamorphic-de-squeeze-white-paper-data.pdf),
   [Wolfcrow](https://wolfcrow.com/anamorphic-workflow-guide-for-mirrorless-cameras/)). Danach haben alle Objekte
   wieder **natürliche Proportionen**. Das gestreckte Bild sieht nicht „gestreckt“ aus, weil es vorher
   gestaucht wurde. Ein 1.33×-Vorsatz am iPhone erweitert den Bildwinkel um ein Drittel
   ([Moondog Labs, No Film School](https://nofilmschool.com/2013/11/moondog-labs-anamorphic-filmmaking-iphone)).
4. Mit dem Desqueeze werden alle Effekte aus Schritt 2 mitgestreckt: Bokeh wird **oval** (aufrechte Ellipsen,
   Verhältnis ≈ Squeeze), Linsenreflexe werden **horizontale Streaks**, Korn und Randunschärfe werden
   **horizontal gelängt**.
5. **Bekannte Abweichungen** realer Objektive: Der Squeeze ist über das Bildfeld nicht ganz konstant, die Bildränder
   wirken stärker gedehnt und weicher
   ([Imagineer SynthEyes: Optics and Symptoms](https://blog.imagineersystems.com/documentation/syntheyes/anamorphicsguide_files/optics_and_symptoms)).
   Bei Nahfokus kann die Mitte weniger gestaucht sein („Anamorphic Mumps“, Fat-Face-Effekt), und ältere Designs
   zeigen Focus Breathing; moderne Objektive wie die ARRI/ZEISS Master Anamorphic korrigieren beides weitgehend
   ([ZEISS](https://www.zeiss.com/consumer-products/us/cinematography/master-anamorphic-lenses.html),
   [ProVideo Coalition](https://www.provideocoalition.com/three-lenses-a-look-at-bokeh-depth-of-field-and-geometry/)).

## Was daraus für ein normales Foto folgt

Aus einem normalen Foto lässt sich **kein zusätzlicher Bildwinkel** herstellen, und ein Strecken des Fotos ersetzt ihn
nicht – es macht nur Gesichter und Objekte breit. Genau das wirkt unnatürlich. Die App streckt deshalb im
Standard **nichts** (Breitenstreckung 1.00×). Die Szene bleibt proportional richtig, der 2.39:1-Rahmen ist ein
Zuschnitt (ein Anamorphot hätte bei gleicher Position links und rechts mehr gezeigt). Was die App stattdessen
nachbaut, sind die **Spuren** der Optik:

| Echte Spur | Umsetzung |
|---|---|
| Ovales Bokeh (≈ Squeeze) | Unschärfe im Raum mit horizontaler Stauchung `1/squeeze`, danach Streckung. Nur Hintergrund (Motivmaske oder Ellipse), dezent |
| Streak-Flares | nur aus kleinen, sehr hellen Lichtquellen des Originals (Top-Hat-Filter), horizontal verschmiert |
| Halation | warmer, ovaler Hof um die Lichter |
| Rand-Mumps | Mitte exakt unverändert, äußerster Rand um wenige Prozent breiter (Standard +8 %) |
| Randunschärfe | zum Rand zunehmende Unschärfe im Sensorraum |
| Ovale Vignette | radialer Abfall, horizontal gestreckt |
| Gelängtes Korn | Korn-Zellen um den Squeeze gestreckt, dezent |
| Farbsäume | laterale chromatische Aberration, null in der Mitte |

Regler dazu im Reiter **Linse → Anamorphot**: *Linsen-Squeeze* (Ovalität), *Breitenstreckung*, *Randdehnung*,
*Randunschärfe*.

## Wann die Breitenstreckung trotzdem sinnvoll ist

- Das Material wurde **wirklich** mit Anamorphot gedreht und liegt noch gestaucht vor (z. B. 1.33× Vorsatz):
  Breitenstreckung = Faktor des Vorsatzes.
- Du willst den gestreckten Look bewusst (Stilmittel, schmale Motive). Bis ca. 1.15× bleibt es unauffällig.

## Nicht nachgebaut

- Mehr Bildwinkel (siehe oben), Focus Breathing, fokusabhängige Mumps – beides hängt an der Entfernung und
  am Objektivdesign und ließe sich aus einem Foto ohne Tiefeninformation nicht glaubwürdig herleiten.
