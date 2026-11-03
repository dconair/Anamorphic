# Wie ein Anamorphot arbeitet – und was die App daraus nachbaut

## Die echte Aufnahme

1. **Squeeze.** Zylindrische Linsenelemente stauchen das Bild nur horizontal (typisch 1.33× bis 2×). Der Sensor sieht
   ein schmales, hohes Bild und nutzt seine ganze Fläche. Das Bild wird *breiter erfasst*, nicht abgeschnitten.
2. **Optik im gestauchten Raum.** Unschärfe, Blendenform, Flares und Randabfall entstehen *vor* dem Sensor, also in
   gestauchter Geometrie. Eine runde Blende wirkt dadurch in der Horizontalen schmaler.
3. **Sensor und Korn.** Filmkorn bzw. Pixelraster sind auf dem Sensor rund und gleichmäßig.
4. **Desqueeze.** In der Postproduktion wird das Bild horizontal wieder um den Squeeze-Faktor gestreckt. Dabei werden
   alle Effekte aus Schritt 2 und 3 mitgestreckt:
   - Bokeh-Scheiben werden **oval** (aufrecht stehende Ellipsen, Verhältnis ≈ Squeeze-Faktor),
   - Lichtreflexe in der Linse werden zu **horizontalen blauen Streaks**,
   - Korn wird minimal **horizontal gelängt**,
   - Vignette und Randunschärfe werden **oval**,
   - die Ränder wirken stärker gedehnt als die Mitte („Mumps“-Effekt), weil der Squeeze nicht perfekt konstant ist.
5. Das Ergebnis hat ein schmaleres Schärfe-Feld und mehr Tiefenstaffelung bei gleicher Brennweite, weil die vertikale
   Brennweite länger ist als die horizontale.

## Die Emulation

Aus einem normalen Foto lässt sich Schritt 1 nicht wirklich rückgängig machen (das zusätzliche Sichtfeld fehlt). Die App
simuliert deshalb Schritt 2–4 so, dass die Spuren dieselben sind:

| Echte Spur | Umsetzung |
|---|---|
| Ovales Bokeh | Unschärfe im Raum mit horizontaler Stauchung `1/squeeze`, danach Streckung. Nur Hintergrund (Motivmaske oder Ellipse) |
| Streak-Flares | nur aus kleinen, sehr hellen Lichtquellen des Originalbildes (Top-Hat-Filter), horizontal verschmiert |
| Halation | warmer, ovaler Hof um die Lichter |
| Rand-Mumps | streifenweise Streckung, Rand stärker als Mitte, mittlere Streckung bleibt exakt `desqueeze` |
| Randunschärfe | zum Rand zunehmende Unschärfe im Sensorraum |
| Ovale Vignette | radialer Abfall, horizontal gestreckt |
| Gelängtes Korn | Korn-Zellen werden um den Squeeze gestreckt, dezente Amplitude |
| Farbsäume | laterale Chromatische Aberration, null in der Mitte |

Regler dazu im Reiter **Linse → Anamorphot**: *Linsen-Squeeze* (Ovalität), *Breitenstreckung*, *Randdehnung*,
*Randunschärfe*.

## Grenzen

- Ein Foto ohne anamorphes Material bleibt eine Emulation. Wer maximal glaubwürdig sein will, dehnt wenig
  (1.1×–1.25×) und lässt die Optik-Effekte dezent.
- 1.33×-Vorsätze am iPhone erzeugen **kein** ovales Bokeh, nur breiteres Bild und Streaks. Für diesen Fall
  Linsen-Squeeze auf 1.0 bis 1.2 stellen.
