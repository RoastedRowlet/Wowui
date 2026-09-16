local V2_TAG_NUMBER = 4

---@param v2Rankings ProviderProfileV2Rankings
---@return ProviderProfileSpec
local function convertRankingsToV1Format(v2Rankings, difficultyId, sizeId)
	---@type ProviderProfileSpec
	local v1Rankings = {}
	v1Rankings.progress = v2Rankings.progressKilled
	v1Rankings.total = v2Rankings.progressPossible
	v1Rankings.average = v2Rankings.bestAverage
	v1Rankings.spec = v2Rankings.spec
	v1Rankings.asp = v2Rankings.allStarPoints
	v1Rankings.rank = v2Rankings.allStarRank
	v1Rankings.difficulty = difficultyId
	v1Rankings.size = sizeId

	v1Rankings.encounters = {}
	for id, encounter in pairs(v2Rankings.encountersById) do
		v1Rankings.encounters[id] = {
			kills = encounter.kills,
			best = encounter.best,
		}
	end

	return v1Rankings
end

---Convert a v2 profile to a v1 profile
---@param v2 ProviderProfileV2
---@return ProviderProfile
local function convertToV1Format(v2)
	---@type ProviderProfile
	local v1 = {}
	v1.subscriber = v2.isSubscriber
	v1.perSpec = {}

	if v2.summary ~= nil then
		v1.progress = v2.summary.progressKilled
		v1.total = v2.summary.progressPossible
		v1.totalKillCount = v2.summary.totalKills
		v1.difficulty = v2.summary.difficultyId
		v1.size = v2.summary.sizeId
	else
		local bestSection = v2.sections[1]
		v1.progress = bestSection.anySpecRankings.progressKilled
		v1.total = bestSection.anySpecRankings.progressPossible
		v1.average = bestSection.anySpecRankings.bestAverage
		v1.totalKillCount = bestSection.totalKills
		v1.difficulty = bestSection.difficultyId
		v1.size = bestSection.sizeId
		v1.anySpec = convertRankingsToV1Format(bestSection.anySpecRankings, bestSection.difficultyId, bestSection.sizeId)
		for i, rankings in pairs(bestSection.perSpecRankings) do
			v1.perSpec[i] = convertRankingsToV1Format(rankings, bestSection.difficultyId, bestSection.sizeId)
		end
		v1.encounters = v1.anySpec.encounters
	end

	if v2.mainCharacter ~= nil then
		v1.mainCharacter = {}
		v1.mainCharacter.spec = v2.mainCharacter.spec
		v1.mainCharacter.average = v2.mainCharacter.bestAverage
		v1.mainCharacter.difficulty = v2.mainCharacter.difficultyId
		v1.mainCharacter.size = v2.mainCharacter.sizeId
		v1.mainCharacter.progress = v2.mainCharacter.progressKilled
		v1.mainCharacter.total = v2.mainCharacter.progressPossible
		v1.mainCharacter.totalKillCount = v2.mainCharacter.totalKills
	end

	return v1
end

---Parse a single set of rankings from `state`
---@param decoder BitDecoder
---@param state ParseState
---@param lookup table<number, string>
---@return ProviderProfileV2Rankings
local function parseRankings(decoder, state, lookup)
	---@type ProviderProfileV2Rankings
	local result = {}
	result.spec = decoder.decodeString(state, lookup)
	result.progressKilled = decoder.decodeInteger(state, 1)
	result.progressPossible = decoder.decodeInteger(state, 1)
	result.bestAverage = decoder.decodePercentileFixed(state)
	result.allStarRank = decoder.decodeInteger(state, 3)
	result.allStarPoints = decoder.decodeInteger(state, 2)

	local encounterCount = decoder.decodeInteger(state, 1)
	result.encountersById = {}
	for i = 1, encounterCount do
		local id = decoder.decodeInteger(state, 4)
		local kills = decoder.decodeInteger(state, 2)
		local best = decoder.decodeInteger(state, 1)
		local isHidden = decoder.decodeBoolean(state)

		result.encountersById[id] = { kills = kills, best = best, isHidden = isHidden }
	end

	return result
end

---Parse a binary-encoded data string into a provider profile
---@param decoder BitDecoder
---@param content string
---@param lookup table<number, string>
---@param formatVersion number
---@return ProviderProfile|ProviderProfileV2|nil
local function parse(decoder, content, lookup, formatVersion) -- luacheck: ignore 211
	-- For backwards compatibility. The existing addon will leave this as nil
	-- so we know to use the old format. The new addon will specify this as 2.
	formatVersion = formatVersion or 1
	if formatVersion > 2 then
		return nil
	end

	---@type ParseState
	local state = { content = content, position = 1 }

	local tag = decoder.decodeInteger(state, 1)
	if tag ~= V2_TAG_NUMBER then
		return nil
	end

	---@type ProviderProfileV2
	local result = {}
	result.isSubscriber = decoder.decodeBoolean(state)
	result.summary = nil
	result.sections = {}
	result.progressOnly = false
	result.mainCharacter = nil

	local sectionsCount = decoder.decodeInteger(state, 1)
	if sectionsCount == 0 then
		---@type ProviderProfileV2Summary
		local summary = {}
		summary.zoneId = decoder.decodeInteger(state, 2)
		summary.difficultyId = decoder.decodeInteger(state, 1)
		summary.sizeId = decoder.decodeInteger(state, 1)
		summary.progressKilled = decoder.decodeInteger(state, 1)
		summary.progressPossible = decoder.decodeInteger(state, 1)
		summary.totalKills = decoder.decodeInteger(state, 2)

		result.summary = summary
	else
		for i = 1, sectionsCount do
			---@type ProviderProfileV2Section
			local section = {}
			section.zoneId = decoder.decodeInteger(state, 2)
			section.difficultyId = decoder.decodeInteger(state, 1)
			section.sizeId = decoder.decodeInteger(state, 1)
			section.partitionId = decoder.decodeInteger(state, 1) - 128
			section.totalKills = decoder.decodeInteger(state, 2)

			local specCount = decoder.decodeInteger(state, 1)
			section.anySpecRankings = parseRankings(decoder, state, lookup)

			section.perSpecRankings = {}
			for j = 1, specCount - 1 do
				local specRankings = parseRankings(decoder, state, lookup)
				table.insert(section.perSpecRankings, specRankings)
			end

			table.insert(result.sections, section)
		end
	end

	local hasMainCharacter = decoder.decodeBoolean(state)
	if hasMainCharacter then
		---@type ProviderProfileV2MainCharacter
		local mainCharacter = {}
		mainCharacter.zoneId = decoder.decodeInteger(state, 2)
		mainCharacter.difficultyId = decoder.decodeInteger(state, 1)
		mainCharacter.sizeId = decoder.decodeInteger(state, 1)
		mainCharacter.progressKilled = decoder.decodeInteger(state, 1)
		mainCharacter.progressPossible = decoder.decodeInteger(state, 1)
		mainCharacter.totalKills = decoder.decodeInteger(state, 2)
		mainCharacter.spec = decoder.decodeString(state, lookup)
		mainCharacter.bestAverage = decoder.decodePercentileFixed(state)

		result.mainCharacter = mainCharacter
	end

	local progressOnly = decoder.decodeBoolean(state)
	result.progressOnly = progressOnly

	if formatVersion == 1 then
		return convertToV1Format(result)
	end

	return result
end
--- the utf8 global is not available, so we polyfill utf8.offset so we can correctly find prefixes of utf8 strings
---@param str string
---@param index number
---@return number|nil
local function Utf8Offset(str, index)
	local len = #str

	if index <= 0 or index > len then
		return nil -- Out of bounds
	end

	-- Move forward to the nth character
	local count = 0
	for i = 1, len do
		local byte = string.byte(str, i)
		local isContinuationByte = byte >= 128 and byte < 192
		if not isContinuationByte then
			count = count + 1
			if count == index then
				return i
			end
		end
	end

	return nil -- If the nth character is not found
end

---@param table table<string, string> raw data table with character name prefixes as keys
---@param length number the number of complete characters to include in the prefix
---@return fun(characterName: string):string|nil getChunk function to retrieve a character chunk by prefix using a complete character name
local function getChunkLookup(table, length)
	return function(characterName)
		local startOfNextCharacter = Utf8Offset(characterName, length + 1)

		local prefix
		if startOfNextCharacter == nil then
			prefix = characterName
		else
			prefix = string.sub(characterName, 1, startOfNextCharacter - 1)
		end

		return table[prefix]
	end
end

local lookup = {'Unknown-Unknown','Shaman-Restoration','Evoker-Devastation','Warlock-Destruction','Warlock-Demonology','Evoker-Augmentation','Druid-Balance','DeathKnight-Blood','Hunter-BeastMastery','Hunter-Marksmanship',}
local provider = {region='US',realm='Draenor',name='US',type='weekly',zone=53,date='2026-09-15',data={Ab='Abhire:BAAANQADCgYIBgABNQAECgMIBAABAAAAAA==.',
Ad='Advisor:BAAANQAECgYIDQAAAA==.',
Ae='Aería:BAABNQAECoEXAAICAAkJsR9UCAA0AwACAAkJsR9UCAA0AwAAAA==.',
Am='Amalia:BAAANQABCgIIAgAAAA==.Amandakk:BAAANQADCgYICwAAAA==.',
An='Angelicuss:BAAANQADCgYIBgABNQAECgQICQABAAAAAA==.',
Ap='Aparajita:BAAANQAECgYICgAAAA==.Aphrodite:BAAANQAECgQIBAAAAA==.',
Ar='Arianda:BAAANQAECgYIDAAAAA==.Aristoleh:BAAANQAECgEIAQABNQAECggIEgABAAAAAA==.Arolder:BAAANQAECgUICgAAAA==.Artemis:BAAANQABCgYIBgABNQAECgQIBAABAAAAAA==.',
As='Astayuno:BAAANQADCgQIBAAAAA==.',
At='Atoadaso:BAAANQAECgQIBAAAAA==.',
Az='Azazél:BAAANQAECgcIDgAAAA==.Azcowboy:BAAANQADCgEIAQAAAA==.Aznå:BAAANQADCgEIAQAAAA==.Azurjinn:BAAANQADCgEIAQAAAA==.',
Ba='Balacheck:BAAANQADCgcIEAAAAA==.Barakka:BAAANQABCgIIAgAAAA==.',
Bb='Bbite:BAAANQAECgQIBgAAAA==.',
Bi='Bigbadwoof:BAAANQADCgMIAwAAAA==.Bipbipbup:BAAANQABCgUIBQAAAA==.',
Bo='Bogarash:BAAANQABCgIIAgAAAA==.Boombástic:BAAANQAECgUIBwAAAA==.Boomco:BAAANQAECgQICQAAAA==.',
Br='Bravillius:BAAANQABCggICwAAAA==.Breeti:BAAANQADCgYIEQAAAA==.Broin:BAAANQADCgQIBAABNQADCgYIDgABAAAAAA==.Bryda:BAAANQADCgYIFAAAAA==.',
Bu='Bubblecreep:BAAANQADCgQIBQABNQAECgMIAwABAAAAAA==.Burblingbee:BAAANQAECgQIBAAAAA==.Butch:BAAANQAECgYIBwAAAA==.Butteskull:BAAANQADCgYIDgAAAA==.',
Bw='Bwucewee:BAAANQADCgYIDwAAAA==.',
Ca='Cajbo:BAAANQAECgMIBAAAAA==.Calyssa:BAAANQAECgYICQAAAA==.Capmkrunch:BAAANQADCgUIBQABNQADCgYICAABAAAAAA==.Capybara:BAAANQAECggIDAAAAA==.Cartan:BAAANQAECgcIEQAAAA==.',
Ch='Charizaardx:BAABNQAECoEgAAIDAAgJFBw/CACTAgADAAgJFBw/CACTAgAAAA==.Chromeski:BAAANQAECgEIAQAAAA==.',
Cl='Cletus:BAAANQAECgIIAgAAAA==.',
Co='Cowdeath:BAAANQADCgcIBwAAAA==.',
Cr='Creedz:BAAANQADCgMIAwAAAA==.Creepymage:BAAANQAECgMIAwAAAA==.Crimsonthot:BAAANQADCgQIBAAAAA==.Crystalys:BAAANQADCgcIFgAAAA==.',
Cu='Cuto:BAAANQADCgIIAgAAAA==.Cuttie:BAAANQADCgYIEAAAAA==.',
Cy='Cyblade:BAAANQAECgYIDwAAAA==.',
Da='Dalna:BAAANQAECgIIAwAAAA==.Darkderek:BAAANQADCgUIDAAAAA==.Darklürker:BAAANQADCgcIGgAAAA==.Darksaber:BAAANQADCgYICgAAAA==.Darkwi:BAABNQAECoEWAAMEAAgJBhCxFwCJAQAEAAYJxRCxFwCJAQAFAAUJ0AuQZQA9AQAAAA==.Dayne:BAAANQAECgMIAwAAAA==.',
De='Deadpool:BAAANQADCgUIBQABNQAECgYIDwABAAAAAA==.Deathby:BAAANQAECgMICgAAAA==.Deathtardza:BAAANQADCggIFQAAAA==.Defiant:BAAANQABCgQIBgAAAA==.Deilliann:BAAANQAECgQIBwAAAA==.Deldawalth:BAAANQAECgIIAgAAAA==.Demonica:BAAANQAECgIIAwAAAA==.Denogginizer:BAAANQADCgcIBwAAAA==.Devick:BAAANQAECgIIAgAAAA==.',
Di='Dimmak:BAAANQADCggIBwAAAA==.Dinta:BAAANQAECgQICQAAAA==.',
Do='Dominoes:BAAANQADCgcIGQAAAA==.Dovahhun:BAAANQADCgYIBgAAAA==.',
Dr='Drakth:BAAANQADCgYIBgAAAA==.',
Du='Dummblond:BAAANQAECgUICgAAAA==.',
Dy='Dysfunction:BAAANQAECgUICAAAAA==.',
['Dä']='Därkstone:BAAANQADCgEIAQAAAA==.',
Ea='Earthshield:BAAANQADCgEIAQABNQAECgQIBgABAAAAAA==.',
Eg='Ego:BAAANQAECgQIBwAAAA==.',
El='Ellaana:BAAANQADCgYICgAAAA==.Ellee:BAAANQABCgYIBgAAAA==.Elotarra:BAAANQADCgUIBgAAAA==.Eluné:BAAANQADCgUIBQAAAA==.',
Em='Emordat:BAAANQAECgEIAQAAAA==.',
Ex='Exine:BAAANQADCggIFAAAAA==.',
Fa='Faethe:BAAANQADCgIIAgABNQAECgQICQABAAAAAA==.Fananabanana:BAAANQADCggIEQAAAA==.',
Fi='Finite:BAAANQADCgQIBAAAAA==.Firewater:BAAANQAECgQICwAAAA==.',
Fl='Flameheart:BAAANQAECgEIAQAAAA==.Fleathulhu:BAAANQAECgUICgAAAA==.Flungpu:BAAANQADCgYIDwABNQAECgMIBQABAAAAAA==.',
Fo='Fostock:BAAANQADCgcIEAAAAA==.',
Fr='Frostmoon:BAAANQABCgYICwAAAA==.Frozty:BAAANQADCgEIAQAAAA==.',
Ga='Galiena:BAAANQADCgQIBAAAAA==.Garwynn:BAAANQAECgUICAAAAA==.',
Gh='Ghostkev:BAAANQAECgMIAwAAAA==.',
Gl='Glaistia:BAAANQADCggIDAAAAA==.Glen:BAAANQADCgYICgAAAA==.Glowstik:BAAANQADCgcICwAAAA==.',
Ha='Habbyb:BAAANQADCgQIBAAAAA==.Habbypallie:BAAANQADCgUICgAAAA==.Halixan:BAAANQAECgcICgAAAA==.Hansdragonis:BAAANQADCgIIAgAAAA==.',
He='Healze:BAAANQADCgUIBQAAAA==.Hellgrin:BAAANQADCgcIEAAAAA==.',
Ho='Holysim:BAAANQADCgEIAQAAAA==.Honir:BAAANQAECgQICQAAAA==.',
['Hâ']='Hâvoc:BAAANQADCgYIEQAAAA==.',
['Hü']='Hünter:BAAANQAECgEIAQAAAA==.',
Ih='Ihlyria:BAAANQADCgIIAgABNQAECgQICQABAAAAAA==.',
Im='Imonster:BAAANQADCgcIBwAAAA==.Imooforu:BAAANQADCgUIBgABNQADCgUIDAABAAAAAA==.',
Ir='Irevoke:BAAANQADCgQIBAAAAA==.Iridia:BAAANQADCgIIAgAAAA==.',
Is='Islet:BAAANQADCgQICAAAAA==.',
Ja='Jaegas:BAAANQAECgIIAgAAAA==.Jamus:BAAANQAECgQIBgAAAA==.Jarvy:BAAANQAECgMIAwAAAA==.',
Ji='Jiangshi:BAAANQADCgQIBAAAAA==.',
Jo='Johnzandalar:BAAANQADCgcICAAAAA==.',
Ka='Kaazel:BAAANQAECgMIBQAAAA==.Kaladiin:BAAANQADCgcIFQAAAA==.Kallias:BAAANQAECgQICQAAAA==.Karite:BAAANQAECgUICAAAAA==.Karlov:BAAANQADCgYIDAAAAA==.Kaymyn:BAAANQAECgUICgAAAA==.Kazar:BAAANQADCgIIAgAAAA==.Kazenoth:BAAANQADCgYIBQAAAA==.',
Ke='Kehjistan:BAAANQAECgEIAQAAAA==.Kennychaoss:BAAANQAECgQICQAAAA==.',
Ki='Kille:BAAANQADCgcIGQAAAA==.Killyoualot:BAAANQAECgQIBAAAAA==.',
Ko='Kosseluna:BAAANQAECgIIAwAAAA==.Kostazu:BAAANQAECgQICQAAAA==.',
La='Laity:BAAANQAECgQIBQAAAA==.Lazariir:BAAANQABCgQIBAAAAA==.',
Le='Lebesgue:BAAANQAECgUIBQABNQAECgcIEQABAAAAAA==.Lebigmu:BAAANQAECgEIAQAAAA==.',
Li='Lisettar:BAAANQAECgIIAwAAAA==.',
Lo='Lockncreep:BAAANQADCgUIDAABNQAECgMIAwABAAAAAA==.Lolwut:BAAANQABCgUICAAAAA==.',
Lu='Luminary:BAAANQAECgQIBAABNQAECgUIBQABAAAAAA==.Lunariss:BAAANQADCgYICQAAAA==.',
Ly='Lycanbyte:BAAANQADCgYIFQAAAA==.Lylith:BAAANQAECgUICAAAAA==.',
Ma='Macryver:BAAANQADCgIIAgAAAA==.Magdalena:BAAANQADCgcIDQAAAA==.Magikos:BAAANQADCgUIBQAAAA==.Magnólia:BAAANQAECgQIBQABNQAECgYIDAABAAAAAA==.Mahan:BAAANQADCgQIBAAAAA==.Maribelle:BAAANQADCgQIBAABNQAECgQICQABAAAAAA==.',
Me='Melomel:BAAANQADCgcIEAAAAA==.Melonsquezer:BAAANQAECgQIBwAAAA==.Menmei:BAAANQADCgcIEAAAAA==.Meow:BAAANQADCggIDgAAAA==.Merphia:BAAANQADCgEIAQAAAA==.Meygen:BAAANQAECgEIAQAAAA==.',
Mi='Milkman:BAAANQABCgEIAQAAAA==.Minien:BAAANQADCggIFwAAAA==.Minko:BAAANQABCgQIBAAAAA==.Minore:BAAANQAECgMIBAAAAA==.',
Mo='Moa:BAAANQAECgIIAgABNQAECgcIDgABAAAAAA==.Moneybadger:BAAANQABCgIIAgAAAA==.Moonshot:BAAANQAECgQICQAAAA==.Moortz:BAAANQADCgMIAwABNQAECgQIBwABAAAAAA==.Morillic:BAAANQAECgUICAAAAA==.Mortegurn:BAAANQABCgYICwAAAA==.',
My='Myros:BAAANQAECgQIBwAAAA==.',
Na='Nantari:BAAANQAECgEIAQABNQAECgQIBwABAAAAAA==.Narestor:BAAANQAECgQIBAABNQAECgcIEgABAAAAAA==.Nazervis:BAABNQAECoEcAAMDAAkJ6CPLAQCAAwADAAkJ6CPLAQCAAwAGAAEJ2x9SEQBUAAAAAA==.',
Ne='Nekopunch:BAAANQAECgQIBAAAAA==.Nelcor:BAAANQADCggICwAAAA==.Nemesîs:BAAANQABCgcICwAAAA==.Newhealer:BAAANQADCggIDgABNQADCggIEQABAAAAAA==.',
No='Noint:BAAANQADCgcIFgAAAA==.Nortree:BAAANQADCgcIEAAAAA==.',
Nu='Nulwyrm:BAAANQAECgQIBQAAAA==.',
Ny='Nymue:BAAANQAECgQIBQAAAA==.Nyyrivik:BAAANQADCgIIAgAAAA==.',
Oc='Octapie:BAAANQAECgUICAAAAA==.',
Oh='Ohitsadragon:BAAANQAECgUIBwAAAA==.',
Oo='Oograshi:BAAANQADCgQIBgAAAA==.',
Or='Oranur:BAAANQAECgEIAgAAAA==.Oreoscruunit:BAAANQADCgYICAAAAA==.Ormil:BAAANQABCgIIAgAAAA==.',
Os='Oscuridad:BAAANQADCgcIGQAAAA==.',
Ow='Owl:BAAANQAECgQIBAAAAA==.Owlcatraz:BAABNQAECoEYAAIHAAkJIhDxHgBDAgAHAAkJIhDxHgBDAgAAAA==.',
Pa='Paendrag:BAAANQADCggIDQAAAA==.Panteragon:BAAANQADCgcIEAAAAA==.Panthean:BAAANQADCgcIFQAAAA==.Papicante:BAAANQAECgEIAQAAAA==.Pashene:BAAANQADCgcIEAAAAA==.',
Pe='Peachyboy:BAAANQADCgMIAwAAAA==.Periwinkle:BAAANQAECgUICAAAAA==.Persaud:BAAANQAECgYIDgAAAA==.Pettacular:BAAANQAECgUICQAAAA==.',
Ph='Phidra:BAAANQAECgUICAAAAA==.',
Po='Poprocks:BAAANQADCgYIFQAAAA==.',
Pr='Predatorc:BAAANQAECgUICQAAAA==.Primevil:BAAANQADCgYIFQAAAA==.Primevl:BAAANQAECgQICQAAAA==.',
Qa='Qamar:BAAANQADCgMIAwAAAA==.',
Ra='Radïance:BAAANQADCgYICQAAAA==.Raediant:BAAANQAECgQIBAAAAA==.Raggaemon:BAAANQAECgEIAQAAAA==.Raquel:BAAANQAECgUICQAAAA==.',
Re='Rede:BAAANQADCgUIDAAAAA==.Reeyou:BAAANQADCgQIBAABNQAECgQIBQABAAAAAA==.Reign:BAAANQADCgcIGgABNQAECgcIDgABAAAAAA==.Relieff:BAAANQADCgYICgAAAA==.Rennistus:BAAANQADCgcIBwAAAA==.Revival:BAAANQADCgEIAQABNQAECgQIBgABAAAAAA==.',
Ri='Rio:BAAANQAECgQICQAAAA==.Ris:BAAANQAECgUICwAAAA==.Ritami:BAAANQAECggIDAAAAA==.',
Ro='Roffy:BAAANQAECgUICAAAAA==.Roknathar:BAAANQAECgQIBwAAAA==.',
Sa='Saerin:BAAANQAECgcIEgAAAA==.Saintmedes:BAAANQADCggICAAAAA==.Sargeth:BAAANQAECgYICwAAAA==.',
Se='Sechiwa:BAAANQADCgEIAQAAAA==.Sedo:BAAANQADCgYIDQAAAA==.Sehlia:BAAANQAECgUIBwAAAA==.Selenis:BAAANQADCggIEQABNQAECgUIDQABAAAAAA==.',
Sh='Shadowmonarc:BAAANQAECgEIAQAAAA==.Shadowwizard:BAAANQAECgYICwAAAA==.Shamania:BAAANQADCgMIAwABNQAECgMIAwABAAAAAA==.Shaomai:BAAANQAFFAEIAgAAAA==.Shariae:BAAANQADCgIIAgAAAA==.Shidandfard:BAAANQAECgcIEAAAAA==.Shifte:BAAANQAECgQICQAAAA==.Shishkä:BAAANQAECgEIAQAAAA==.Shiv:BAAANQADCgQIBgABNQAECgIIAgABAAAAAA==.Shockabeotch:BAAANQAECgQIBAAAAA==.',
Si='Silverwin:BAAANQADCgYIBgAAAA==.',
Sk='Skädi:BAAANQAECgQIBAAAAA==.',
Sl='Slaughter:BAAANQADCgUIBwAAAA==.Slimage:BAAANQAECgQIBgAAAA==.Slushius:BAAANQADCgEIAQAAAA==.',
Sm='Smittens:BAAANQADCggIEQAAAA==.',
Sn='Snakmag:BAAANQADCgQIBAAAAA==.',
So='Sorn:BAAANQAECgIIBAAAAA==.',
Sp='Spaarkle:BAAANQADCgcIFgAAAA==.Spectrehawk:BAAANQADCgIIAgABNQAECggIGQAIAAkiAA==.Speçtre:BAABNQAECoEZAAIIAAgJCSKkCQAdAwAIAAgJCSKkCQAdAwAAAA==.',
Su='Supak:BAAANQAECgIIAgAAAA==.Suppabad:BAAANQAECgUICAAAAA==.',
['Sá']='Sákura:BAAANQADCgIIAgAAAA==.',
['Sâ']='Sâintdank:BAAANQAECggIBwAAAA==.',
['Så']='Såmæl:BAAANQADCgEIAQAAAA==.',
Ta='Taara:BAAANQADCgEIAQABNQAECgQICQABAAAAAA==.Tadlight:BAAANQADCgYIDgAAAA==.Tarok:BAAANQADCgYIBgAAAA==.Tazara:BAAANQADCgIIAgAAAA==.',
Tb='Tbone:BAAANQADCgUIBQAAAA==.',
Te='Teapha:BAAANQAECgQIBQAAAA==.Ted:BAAANQAECgQIBwAAAA==.Temptressxx:BAAANQAECgUICAAAAA==.Tenstar:BAAANQAECgMIAwAAAA==.',
Th='Thekingheals:BAAANQAECgQIBAABNQAECgcIDQABAAAAAA==.Thokmay:BAAANQADCggIFwAAAA==.Thorel:BAAANQADCgYIBgAAAA==.Thunden:BAAANQADCgYIEQAAAA==.Thunderon:BAAANQABCgEIAQAAAA==.',
Ti='Tiandrinna:BAAANQAECgYIDAAAAA==.Tigirius:BAAANQADCgQIBQAAAA==.Timkaoss:BAAANQADCgYIEwAAAA==.',
Tm='Tmagnet:BAAANQADCgcIEAAAAA==.',
To='Totemology:BAAANQADCgYICQAAAA==.',
Tr='Tripwire:BAAANQADCgEIAQAAAA==.',
Tw='Tweedildee:BAAANQAECgYIEAAAAA==.',
['Tà']='Tàttersail:BAAANQADCgYIDwAAAA==.',
Un='Unholycreep:BAAANQADCgIIAgABNQAECgMIAwABAAAAAA==.',
Va='Valdor:BAAANQAECgQICQAAAA==.Valicous:BAAANQADCgYIFQAAAA==.Vandalie:BAAANQADCggICgABNQAECgQIBAABAAAAAA==.Vaylorian:BAAANQAECggIDwAAAA==.Vaült:BAAANQAECgUICAAAAA==.',
Ve='Vellathor:BAAANQADCgQIBQAAAA==.Velocity:BAAANQAECgQIBAAAAA==.Verianna:BAAANQAECgUIDQAAAA==.',
Vi='Virelya:BAAANQADCgEIAQABNQAECgcIDgABAAAAAA==.',
Vo='Vodkâshots:BAAANQAECggICAAAAA==.Voidbinder:BAAANQADCgQIBAABNQAFFAEIAgABAAAAAA==.',
Wa='Wadumu:BAAANQABCgIIAgAAAA==.Warvegas:BAAANQADCgYIBgAAAA==.',
Wi='Willowy:BAAANQAECgQICQAAAA==.',
['Wâ']='Wâlmi:BAAANQAECgQIBwAAAA==.',
Xa='Xaerius:BAAANQAECgUICAAAAA==.Xantyr:BAAANQADCgYIDAAAAA==.',
Ya='Yarman:BAAANQADCgcIEAAAAA==.',
Yo='Yojimbro:BAAANQADCgYIEgAAAA==.Yoshial:BAAANQADCgEIAQAAAA==.',
Za='Zaelen:BAAANQADCgIIAgAAAA==.Zainadin:BAAANQADCgYICgAAAA==.Zalantir:BAAANQAECgYIDQABNQAECggIHQAJALskAA==.Zariski:BAAANQAECgEIAQABNQAECgcIEQABAAAAAA==.Zarthus:BAAANQADCgMIAwAAAA==.',
Ze='Zealantis:BAAANQADCgMIAwAAAA==.Zealins:BAAANQAECgQIBwAAAA==.',
Zi='Zirl:BAAANQAECgEIAgABNQAECggIHQAJALskAA==.Ziyn:BAABNQAECoEdAAMJAAgJuyRhBwBcAwAJAAgJ8yNhBwBcAwAKAAYJ2x01HQDDAQAAAA==.',
Zo='Zoplete:BAAANQABCgIIBAAAAA==.',
['Án']='Ángél:BAAANQADCgIIAgAAAA==.',
['Ýa']='Ýachiru:BAAANQADCgYICAAAAA==.',
['Ÿe']='Ÿeñnefer:BAAANQADCgYIDQAAAA==.',
},}
provider.parse = parse

local rawData = provider.data
provider.data = {}
provider.getChunk = getChunkLookup(rawData, 2)

provider.splitId = 0
provider.splitCount = 1
provider.splitType = 'none'

setmetatable(provider.data, {
	__index = function(table, key)
		provider.getChunk(key)
	end,
})

if _G["ArchonTooltip"] and ArchonTooltip.AddProviderV2 then
	ArchonTooltip.AddProviderV2(lookup, provider)
end
