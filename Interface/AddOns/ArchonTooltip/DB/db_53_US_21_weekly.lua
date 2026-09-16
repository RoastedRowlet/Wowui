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

local lookup = {'Unknown-Unknown','Evoker-Preservation','Druid-Guardian','DeathKnight-Blood','Monk-Brewmaster','Shaman-Restoration','Rogue-Outlaw','Druid-Balance','Paladin-Retribution','Shaman-Elemental','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Paladin-Holy','Warrior-Arms','Druid-Feral','Priest-Shadow','Priest-Holy','DeathKnight-Frost',}
local provider = {region='US',realm='Arygos',name='US',type='weekly',zone=53,date='2026-09-15',data={Aa='Aaryssian:BAAANQADCgYIBgAAAA==.',
Ab='Abattoire:BAAANQADCgIIAgAAAA==.Abbyrose:BAAANQABCggICgAAAA==.',
Ad='Adrenelian:BAAANQADCggIDgAAAA==.',
Ak='Akroma:BAAANQAECgMIAwAAAA==.',
Al='Allyon:BAAANQADCgMIAwAAAA==.Altezio:BAAANQAECgcIEQAAAA==.',
Am='Amargue:BAAANQADCgEIAQAAAA==.Amorial:BAAANQADCgEIAQAAAA==.',
An='Anbraxas:BAAANQABCgMIAwAAAA==.Ankarna:BAAANQADCgUIDQAAAA==.Annegwish:BAAANQAECgYICwAAAA==.',
Ap='Apah:BAAANQADCgYIBgAAAA==.',
Ar='Arathon:BAAANQAECgIIAwAAAA==.Arclight:BAAANQAECgQICAAAAA==.Ardiana:BAAANQADCggICAAAAA==.Ardimis:BAAANQADCgYIBgAAAA==.Ardithan:BAAANQAECgcIDwAAAA==.Arthuur:BAAANQAECgYICQABNQAECgcIBwABAAAAAA==.Arykami:BAAANQAECgIIAgABNQAECgkJHgACAFceAA==.Arypto:BAAANQADCggICAABNQAECgkJHgACAFceAA==.Arystrasza:BAABNQAECoEeAAICAAkJVx6sAwA+AwACAAkJVx6sAwA+AwAAAA==.Aryzhuque:BAAANQAECgEIAQABNQAECgkJHgACAFceAA==.',
As='Ashmandious:BAAANQAECgQIBgAAAA==.Assandros:BAABNQAECoEeAAIDAAkJ9yU5AADwAwADAAkJ9yU5AADwAwAAAA==.',
At='Athleta:BAEANQAFFAQIBAABNQAFFAYIEgAEANsVAA==.',
Av='Average:BAAANQADCgMIAwABNQADCgUIBQABAAAAAA==.',
Ba='Balkaj:BAAANQADCgEIAQAAAA==.Banthum:BAAANQAECgQIBAAAAA==.',
Be='Beerhelmet:BAAANQAECgMICAAAAA==.Beryl:BAAANQAECgEIAQAAAA==.',
Bi='Biggyword:BAAANQAECgQIBAAAAA==.Bingchow:BAAANQADCgQIBAABNQADCgYIBgABAAAAAA==.',
Bl='Blorbusdorp:BAAANQADCgUICAAAAA==.',
Bo='Bobsgirl:BAAANQAECgcIDwAAAA==.Bowser:BAAANQAECgEIAQAAAA==.',
Br='Braleanna:BAAANQADCgcIEAAAAA==.',
Bu='Bugge:BAAANQADCgcIDQAAAA==.',
Cb='Cbat:BAAANQAECgQIBAAAAA==.',
Cd='Cdicepalta:BAAANQAECgUICgAAAA==.',
Ce='Celes:BAAANQADCgMIAwAAAA==.Cetera:BAAANQAECgQIBAAAAA==.',
Ch='Chapulín:BAAANQAECgcIEgABNQAECgkJHgAFAH4jAA==.',
Co='Confettii:BAAANQABCgQIBQABNQADCgUICQABAAAAAA==.',
Ct='Ctrlaltshot:BAAANQADCggICgAAAA==.',
Cu='Cutedeath:BAAANQADCgIIAgAAAA==.Cuteretsu:BAAANQABCgYIBwAAAA==.',
Da='Dalus:BAAANQAECgQIBAAAAA==.Dankzìlla:BAAANQAECgYIBgAAAA==.Darington:BAAANQAECgcIEgAAAA==.Darkslayers:BAAANQADCgMIAwABNQAECgMIBAABAAAAAA==.Dawny:BAABNQAECoEeAAIGAAkJbQ7FKgAXAgAGAAkJbQ7FKgAXAgAAAA==.Daywalkers:BAAANQAECgMIBAAAAA==.',
De='Dethndk:BAAANQAECgcICgAAAA==.',
Di='Die:BAABNQAECoEbAAIHAAkJqBVhAwCPAgAHAAkJqBVhAwCPAgAAAA==.',
Do='Doorjob:BAAANQAECgcIEQAAAA==.Doràn:BAAANQADCggICAABNQAFFAYICgACAAAHAA==.',
Dr='Dreadravens:BAAANQADCgUIBQAAAA==.Dreamily:BAABNQAECoEeAAIIAAkJ8xK0GwBnAgAIAAkJ8xK0GwBnAgAAAA==.Dreamtalker:BAAANQABCggIDwAAAA==.Dråcø:BAAANQADCgUIBQAAAA==.',
Du='Dumpy:BAAANQADCgQIBAAAAA==.',
Ej='Eji:BAAANQABCgYICQAAAA==.',
El='Elenyia:BAAANQAECgMIAwAAAA==.Elia:BAAANQAECgcIDwAAAA==.Elmo:BAAANQAECgcIEQAAAA==.Elurrmental:BAAANQADCgcIFAAAAA==.',
Em='Emaria:BAAANQADCgYIGwAAAA==.Emergencii:BAAANQABCgMIBQABNQADCgUICQABAAAAAA==.Emp:BAAANQADCgYIBgAAAA==.',
En='Enemor:BAAANQADCgMIAwAAAA==.Entranced:BAAANQAECgUICgAAAA==.Entropius:BAAANQAECgQIBAAAAA==.',
Er='Eranica:BAAANQADCgIIAgAAAA==.Ereinion:BAAANQAECgQIBwAAAA==.',
Ey='Eyb:BAAANQADCggIFQAAAA==.',
Ez='Ezayle:BAABNQAECoEeAAIJAAkJnhDPOAAbAgAJAAkJnhDPOAAbAgAAAA==.',
Fe='Fearsmage:BAAANQABCgIIAgAAAA==.Femto:BAAANQAECgIIAgAAAA==.',
Fl='Flogg:BAAANQADCgEIAQAAAA==.',
Fo='Fonzie:BAABNQAECoEYAAIKAAkJKg7WKQAsAgAKAAkJKg7WKQAsAgAAAA==.Foregotten:BAAANQAECgcIEgAAAA==.',
Fr='Frostietute:BAAANQAECgEIAQABNQAECgYICwABAAAAAA==.',
Fu='Furysmight:BAAANQAECgcIBwAAAA==.',
Ga='Gabrielle:BAAANQADCgcIBwABNQAECgcICwABAAAAAA==.Gamboa:BAAANQAECgEIAQAAAA==.Gauche:BAAANQAECgEIAQAAAA==.Gazreiale:BAAANQAECgQICQAAAA==.',
Gi='Gimlet:BAAANQADCgMIAwAAAA==.',
Gr='Grass:BAAANQAECgEIAQAAAA==.Grÿmm:BAAANQAECgQIBgAAAA==.',
Gu='Guldanica:BAAANQADCggIEAAAAA==.Gunn:BAAANQADCgQIAwAAAA==.',
Gw='Gwaine:BAAANQAECgEIAQAAAA==.Gwin:BAAANQAECggICAAAAA==.Gwyndolín:BAAANQADCgYIBgAAAA==.',
Ha='Hamslamwich:BAAANQADCgcIDgABNQADCggIBwABAAAAAA==.',
He='Hellfyrê:BAAANQAECgIIAgAAAA==.Heritikylust:BAAANQAECgYIDQAAAA==.',
Hi='Hibou:BAAANQADCgcIBgAAAA==.',
Ho='Holyhero:BAAANQAECgYIDQAAAA==.',
Il='Ilectra:BAAANQAECgUICwAAAA==.',
In='Insanitii:BAAANQABCgQIBgABNQADCgUICQABAAAAAA==.',
Ip='Ipoopied:BAAANQADCgQIBAAAAA==.',
Is='Ishmara:BAAANQAECgEIAQAAAA==.',
Ja='Janorune:BAAANQABCggICQAAAA==.',
Je='Jeudeu:BAAANQADCgQIBAAAAA==.',
Jt='Jthaka:BAAANQADCgYIBgAAAA==.',
Ka='Kabira:BAAANQADCggIEQAAAA==.Kaimed:BAAANQABCgIIAgAAAA==.Kalyth:BAAANQAECgUIBwAAAA==.',
Ke='Keionselin:BAAANQABCgYIBgAAAA==.Kepec:BAAANQADCgYICwABNQAECgEIAQABAAAAAA==.',
Kr='Krakkd:BAAANQADCgcIBwAAAA==.Krimzonbrezz:BAAANQADCgYICgAAAA==.Krimzondawn:BAAANQADCgIIAgABNQADCgYICgABAAAAAA==.Krimzonstorm:BAAANQADCgMIAwABNQADCgYICgABAAAAAA==.',
Ku='Kunaee:BAAANQADCgcIDwAAAA==.',
Ky='Kyrius:BAAANQADCggICQABNQAECgQIBQABAAAAAA==.',
['Kì']='Kìku:BAAANQAECgQIBAAAAA==.',
La='Lausia:BAAANQAECgQIBAABNQAECgUICwABAAAAAA==.',
Ld='Ldyrose:BAAANQADCgYIEAAAAA==.',
Le='Leilarose:BAAANQABCgcIBwAAAA==.Lewtiefroopz:BAAANQAECgQIBAAAAA==.',
Li='Lilblade:BAAANQABCgcICQABNQABCggIDwABAAAAAA==.',
Lo='Lottathicc:BAAANQADCgMIAwAAAA==.',
Ly='Lyren:BAAANQADCgMIAwAAAA==.',
['Lì']='Lìlìth:BAAANQADCgYIBgAAAA==.',
['Lï']='Lïghthammer:BAAANQABCgYICQABNQADCgMIAwABAAAAAA==.',
Ma='Macabre:BAAANQAECgMIBAAAAA==.Magnificò:BAAANQAECgQIBAAAAA==.Makani:BAAANQAECgMIAwAAAA==.Malory:BAAANQAECgYICwABNQAECgcICwABAAAAAA==.Malzahär:BAABNQAECoEZAAQLAAkJWCDKGACfAgALAAcJkyDKGACfAgAMAAUJpRxKEwCzAQANAAMJax3YCgDtAAAAAA==.Maress:BAAANQABCgEIAQAAAA==.Marician:BAAANQAECgEIAgAAAA==.Matadore:BAAANQADCgYIBgAAAA==.',
Mi='Miniraven:BAAANQADCgUIBQAAAA==.',
Mo='Mortìs:BAAANQABCgQIBAAAAA==.',
Mu='Muahahaha:BAAANQADCggIBwAAAA==.Muffintop:BAAANQAECgQIBAAAAA==.',
My='Mythalyn:BAAANQADCgYIBgAAAA==.Mythrondrir:BAAANQAECgYIDAAAAA==.Mythundas:BAAANQADCgYIBgAAAA==.',
['Mø']='Møurningsøul:BAAANQABCgQICAABNQADCgMIAwABAAAAAA==.',
Ne='Neosnÿper:BAAANQAECgMIAwABNQAECgcIEwABAAAAAA==.',
Ni='Nielic:BAAANQAECgQIBwAAAA==.Nimbus:BAAANQADCggICAABNQAECgkJTwAKAJckAA==.',
No='Norrahh:BAAANQADCgcIFgAAAA==.Nozzle:BAAANQADCgYIBgAAAA==.',
Om='Omgitsmagic:BAAANQABCgQIBwAAAA==.',
On='Ongo:BAAANQAECgUICQAAAA==.',
Or='Orion:BAAANQAECgMIAwAAAA==.',
Pa='Palapoxi:BAABNQAECoEgAAIOAAkJ4B5TBwBIAwAOAAkJ4B5TBwBIAwAAAA==.',
Pe='Penelopè:BAABNQAECoEeAAIFAAkJfiPzAAChAwAFAAkJfiPzAAChAwAAAA==.Penelópe:BAAANQADCgEIAQABNQAECgkJHgAFAH4jAA==.Penný:BAAANQAECgEIAQABNQAECgkJHgAFAH4jAA==.Pepino:BAAANQAECgIIAgAAAA==.',
Ph='Phinx:BAAANQAECgcIEwAAAA==.Phocheux:BAAANQAECgQICAAAAA==.',
Pi='Pierogi:BAAANQADCgYIBgAAAA==.Pippersy:BAAANQADCgcIEQAAAA==.Piston:BAAANQAECgIIAwAAAA==.',
Po='Poco:BAAANQAECggIBAAAAA==.Poetrii:BAAANQADCgUICQAAAA==.Pomickyal:BAAANQAECgQIBAAAAA==.Ponn:BAAANQAECgEIAQAAAA==.',
Ps='Pshamanthe:BAAANQADCggIFQAAAA==.',
Py='Pyssmissile:BAAANQAECgEIAQAAAA==.',
Qu='Quantumleaf:BAAANQADCgQIBAAAAA==.',
Ra='Raeline:BAAANQADCgQICAAAAA==.Ragnärok:BAAANQAECgcIEgAAAA==.',
Re='Reelwor:BAAANQAECgMIBQAAAA==.Rendskaar:BAABNQAECoEbAAIEAAkJ6B4nCQAlAwAEAAkJ6B4nCQAlAwAAAA==.Reverii:BAAANQABCgYICAABNQADCgUICQABAAAAAA==.Rezelda:BAAANQADCgEIAQAAAA==.',
Rj='Rj:BAAANQAECgMIAwAAAA==.',
Ro='Roughbbq:BAAANQADCgEIAQABNQAECgMIBAABAAAAAA==.',
Rt='Rtpopham:BAAANQAECgIIAgAAAA==.',
['Rá']='Rándy:BAAANQAECgQIBAAAAA==.',
Sa='Saikus:BAAANQAECgMIAwAAAA==.Saphrin:BAAANQAECgIIAgAAAA==.Sardiirn:BAAANQAECgEIAQABNQAECgMIBAABAAAAAA==.',
Sc='Scarfiend:BAAANQADCgMIAwAAAA==.Scurus:BAAANQAECgQIBgAAAA==.',
Se='Selynne:BAABNQAECoEeAAIJAAkJyCDmDwAjAwAJAAkJyCDmDwAjAwAAAA==.',
Sh='Shamanizeds:BAAANQADCggIEQABNQAECgMIBAABAAAAAA==.Shamwisegamg:BAAANQADCgYIBgAAAA==.Shankems:BAAANQADCgEIAQAAAA==.Shifted:BAAANQAECgYIDQAAAA==.Shotgirl:BAAANQADCgEIAQAAAA==.',
Si='Siggie:BAAANQADCgYIDQAAAA==.Sindorei:BAAANQADCgMIAwAAAA==.Sixligma:BAAANQAECgEIAQAAAA==.',
Sk='Skye:BAAANQADCggICwABNQAECgcIEgABAAAAAA==.',
Sl='Slorrin:BAABNQAECoEeAAIPAAkJKyVQAwDIAwAPAAkJKyVQAwDIAwAAAA==.',
So='Solazreiale:BAAANQADCgcIFgAAAA==.Somers:BAAANQADCgMIAwAAAA==.Soulistic:BAAANQABCggIDgAAAA==.',
Sp='Spellbind:BAAANQADCggIDwAAAA==.',
St='Starstorms:BAAANQAECgQIBAAAAA==.',
Sy='Syniz:BAAANQAECgQIBAAAAA==.',
Ta='Taie:BAAANQAECgIIAgAAAA==.Taiez:BAAANQADCggIHAAAAA==.Tauming:BAAANQAECgIIAgAAAA==.',
Te='Teshala:BAAANQAECgQIBAAAAA==.',
Th='Tharil:BAAANQABCgMIBAAAAA==.Therapii:BAAANQABCgQIBQABNQADCgUICQABAAAAAA==.Thesledge:BAAANQAECgUICQAAAA==.',
Ti='Tifalockhàrt:BAAANQAECgcIEgAAAA==.Timewarped:BAAANQAECgYICgAAAA==.',
Tr='Trapsin:BAAANQAECgcIEAAAAA==.Treeage:BAABNQAECoEXAAQQAAgJhg42BwD4AQAQAAgJhg42BwD4AQADAAEJtgTkJwAwAAAIAAEJawERfwAXAAAAAA==.Trufflé:BAAANQAECgQIBAAAAA==.Trustportal:BAAANQADCggIEgABNQAECgMIAwABAAAAAA==.Tryniti:BAAANQADCgIIAgAAAA==.',
Ty='Tyg:BAAANQAECgcIEwAAAA==.',
Un='Unholychow:BAAANQADCgYIBgAAAA==.Uny:BAAANQADCgEIAQABNQAECgUICwABAAAAAA==.',
Us='Usdaprime:BAAANQADCgcICgAAAA==.',
Va='Valstan:BAAANQADCgcIFwAAAA==.Valzyn:BAAANQAECgIIAgAAAA==.',
Ve='Velanora:BAAANQADCgMIBQAAAA==.Verdantclaw:BAAANQABCgUIBgAAAA==.',
Vi='Vivix:BAABNQAECoEeAAMRAAkJFxS1EABcAgARAAgJhxW1EABcAgASAAUJ/hFKTgBGAQAAAA==.',
Vo='Voidedknight:BAAANQADCggICAAAAA==.',
Wa='Wapoxi:BAAANQAECgEIAQABNQAECgkJIAAOAOAeAA==.Warisfluffy:BAAANQAECgQIBAAAAA==.',
We='Welshie:BAAANQADCgEIAQAAAA==.Westnasty:BAAANQADCgEIAQAAAA==.',
Wo='Worldboss:BAAANQAECgMIAwAAAA==.Worldwar:BAAANQADCggIDgAAAA==.',
Wr='Wradalin:BAABNQAECoEZAAITAAgJAR7fCgCrAgATAAgJAR7fCgCrAgAAAA==.Wraithstorm:BAAANQADCgcIFwAAAA==.',
Yu='Yunera:BAAANQADCgYIBgAAAA==.',
Za='Zalor:BAAANQABCgYIBAAAAA==.Zarila:BAAANQADCgcIFgAAAA==.Zartain:BAAANQAECgQIBAAAAA==.',
Ze='Zenizho:BAAANQADCgUIBQAAAA==.Zennamite:BAAANQAECgQIBAAAAA==.',
Zi='Zipzaps:BAAANQADCggIHQAAAA==.',
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
