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

local lookup = {'Unknown-Unknown','Shaman-Restoration','Priest-Shadow','Paladin-Holy','Shaman-Enhancement','DeathKnight-Blood','Rogue-Subtlety','Warlock-Demonology','Warlock-Destruction','Mage-Arcane','DemonHunter-Havoc','Priest-Holy','Priest-Discipline','Hunter-BeastMastery','DeathKnight-Frost','Evoker-Devastation','Monk-Mistweaver','DeathKnight-Unholy','Evoker-Augmentation','Evoker-Preservation','Warlock-Affliction','Rogue-Assassination',}
local provider = {region='US',realm='Dragonblight',name='US',type='weekly',zone=53,date='2026-09-29',data={Aa='Aazula:BAAANQAECgUIBQAAAA==.',
Ab='Aburocket:BAAANQAECgIIAgAAAA==.',
Ad='Adelphie:BAAANQADCgcJCwABNQAECgUICQABAAAAAA==.',
Ak='Akusenshi:BAAANQAECgMIBQAAAA==.',
Al='Albertwesker:BAAANQADCgYIBgAAAA==.Alethrix:BAAANQADCgIIAgAAAA==.Alzith:BAAANQADCgEIAQABNQAECgQIBwABAAAAAA==.',
An='Anderon:BAAANQAECgMIBAAAAA==.Animocity:BAAANQAECgIIAgAAAA==.',
Ap='Apexalpha:BAAANQADCgMJAwAAAA==.',
Ar='Arkayz:BAAANQAECgQIBAAAAA==.Arold:BAAANQAECgYIEAAAAA==.',
As='Asylia:BAACNQAFFIEJAAICAAQKoRMpCgBKAQACAAQKoRMpCgBKAQA1AAQKgRYAAgIACQphIE0QABkDAAIACQphIE0QABkDAAAA.',
Av='Avesiren:BAAANQADCgQIBAAAAA==.',
Az='Azryll:BAAANQAECgIIAgAAAA==.',
Ba='Babalú:BAAANQAECgUICAAAAA==.Babymamaa:BAAANQADCgQIBAAAAA==.Babymuffins:BAAANQADCggIIQAAAA==.Barcaust:BAAANQAECgQIBwAAAA==.',
Be='Beargryllis:BAAANQAECgUIBgAAAA==.Beecrafty:BAAANQADCggIIAAAAA==.Belin:BAAANQADCgIIAgAAAA==.Belligeranta:BAAANQADCgEIAQAAAA==.Beltaloda:BAAANQADCgcIBwAAAA==.',
Bi='Biras:BAAANQADCgYICgAAAA==.',
Bl='Blackmill:BAAANQADCggIEgAAAA==.',
Bo='Board:BAAANQAECgYIEQABNQAECgkJJwADACsaAA==.Bolf:BAAANQAECgEIAQAAAA==.Boombaaby:BAAANQAECgMIBQAAAA==.Bopples:BAABNQAECoErAAIEAAkKKiSPAgC6AwAEAAkKKiSPAgC6AwAAAA==.',
Br='Breakthings:BAAANQAECgUIBQAAAA==.Britishchick:BAAANQAECgQICQAAAA==.Brunhilian:BAAANQADCgUIEQAAAA==.',
Ca='Cadun:BAAANQADCggIIQAAAA==.Cakeismoist:BAAANQADCggICgAAAA==.Calada:BAAANQAECgEIAQAAAA==.Callypso:BAAANQADCggIIgAAAA==.Carbion:BAAANQADCggJCAAAAA==.Cariono:BAABNQAECoEcAAIFAAgKjhKcDgBAAgAFAAgKjhKcDgBAAgAAAA==.Cathsdh:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.Cathslock:BAAANQADCgYIBwABNQAECgIIAgABAAAAAA==.Cathsmage:BAAANQAECgIIAgAAAA==.',
Ce='Cedarnia:BAAANQAECgEIAQAAAA==.',
Co='Corrynn:BAAANQAECgUJBQAAAA==.',
Cr='Cribbage:BAAANQADCgYIBgABNQAECgkJIwAGAHUcAA==.Crimsonlight:BAAANQAECgUIBgAAAA==.',
Cv='Cvaluenigma:BAAANQAECgYIEgAAAA==.',
Cy='Cynosure:BAAANQAECgcJBwAAAA==.Cytronsneak:BAAANQADCgYICgAAAA==.',
Da='Daliå:BAAANQADCgYICQAAAA==.Dalrook:BAAANQAECgIIAwAAAA==.Darkheaven:BAAANQAECgUIDQAAAA==.Darkhunntres:BAAANQADCgEIAQAAAA==.Darknyss:BAAANQADCggIDwAAAA==.Darrling:BAAANQADCgYIBgAAAA==.Davethelock:BAAANQADCgIJAgAAAA==.Dazarek:BAAANQADCggIDAAAAA==.',
De='Deathrazor:BAAANQAECgQIAwAAAA==.Delanir:BAAANQAECgIIAgAAAA==.Demonbarbie:BAAANQADCggJGgAAAA==.Denae:BAAANQAECgUICQAAAA==.Desiinnorre:BAAANQADCgYIEwAAAA==.Devinetoro:BAAANQAECgIIBAAAAA==.Devour:BAAANQAECgYJCgAAAA==.',
Di='Diag:BAAANQAECgQICAAAAA==.Diamos:BAAANQAECgQJCQAAAA==.Dijiaih:BAAANQAECgIIAgAAAA==.',
Dk='Dklunar:BAAANQADCgQJBAABNQAFFAcIGAAEAKgfAA==.',
Do='Doctryn:BAAANQADCgUIBQAAAA==.Dopo:BAAANQADCggIGAAAAA==.',
Dw='Dwangler:BAAANQADCgYICQAAAA==.Dwydeshuse:BAAANQADCgUJDAAAAA==.',
Ea='Ears:BAAANQABCgUIBwAAAA==.',
Ei='Einheri:BAAANQAECgYIDAAAAA==.',
El='Elalian:BAAANQAECgYIEwAAAA==.Elracc:BAAANQADCgIJAgAAAA==.',
En='Endeavour:BAABNQAECoEiAAIHAAgKOh0ZCwCpAgAHAAgKOh0ZCwCpAgAAAA==.Enoira:BAAANQABCgMJBQAAAA==.Enver:BAAANQADCgUIBQAAAA==.',
Ep='Epistle:BAAANQAECgEIAQAAAA==.',
Er='Erfing:BAAANQADCgYJBgAAAA==.',
Eu='Eupi:BAAANQADCggICAAAAA==.',
Fa='Faffard:BAAANQAECgEIAQABNQAECgYIEQABAAAAAA==.Fame:BAAANQADCggIEAABNQAFFAYIFAAEALMBAA==.Farsighted:BAAANQADCgYICAAAAA==.',
Fe='Fennerick:BAAANQADCgQIBgAAAA==.Ferio:BAAANQADCggIGgAAAA==.Feyndra:BAAANQADCgcJEQAAAA==.',
Fi='Fishfire:BAAANQAECgIIAwAAAA==.',
Fu='Funenix:BAAANQABCggIFAAAAA==.',
Fy='Fystie:BAAANQAECgEIAQABNQAECgYIEQABAAAAAA==.',
Ga='Galpally:BAAANQAECgQIBAAAAA==.',
Ge='Gebra:BAAANQAECgIIAwAAAA==.',
Gh='Ghenghiskhan:BAAANQAECgQIBQAAAA==.',
Gi='Gilvader:BAAANQABCgQIBgAAAA==.',
Gl='Glorak:BAAANQAECgMIAwAAAA==.',
Gr='Grashen:BAAANQAECgIIBAAAAA==.Gravorik:BAAANQAECgYJEgAAAA==.Grimxmama:BAAANQADCgIIAgAAAA==.Grixxi:BAAANQAECgIJAwAAAA==.Grogu:BAAANQAECgIIAgAAAA==.',
Gs='Gsm:BAAANQAECgQICAAAAA==.',
Gu='Gurlyman:BAAANQADCgcICwAAAA==.',
Ha='Halyon:BAAANQAECgIIAgAAAA==.Hante:BAAANQADCgEIAQAAAA==.',
He='Hellblazer:BAABNQAECoEYAAMIAAcKdAUnnwAzAQAIAAcKdAUnnwAzAQAJAAIKhgJJYQBJAAAAAA==.',
Ho='Hobuul:BAAANQADCgYIDAAAAA==.Holydps:BAABNQAECoEbAAIEAAcKxh/QKwB/AgAEAAcKxh/QKwB/AgAAAA==.Hoofnstien:BAAANQAECgQIBAAAAA==.Hoompukka:BAAANQADCggIDAAAAA==.Hotspur:BAAANQAECgMIAwAAAA==.',
Hu='Huntermotz:BAAANQADCgYIBgAAAA==.',
Il='Iliketurtles:BAAANQADCggIDAABNQAECggIGQAKAE8TAA==.Ilokana:BAAANQADCgUICgAAAA==.',
Im='Imwithhir:BAAANQAFFAIIAgAAAA==.',
Ir='Ironfist:BAAANQADCgYIGAAAAA==.',
It='Itadori:BAAANQAECgIIAwAAAA==.',
Ja='Jacsknight:BAAANQADCgEJAQAAAA==.Jacspally:BAAANQAECgMJBAAAAA==.Janora:BAAANQAECgYIEgAAAA==.',
Je='Jellexy:BAAANQAECgEIAQAAAA==.',
Jh='Jhazy:BAAANQAECggIEQABNQAFFAcIGwALAFEUAA==.',
Jo='Jolah:BAABNQAECoEbAAMMAAgKOhz7NQBMAgAMAAgKaxn7NQBMAgANAAMK3xnEEADkAAAAAA==.',
Ka='Kaehlen:BAAANQADCggJCAAAAA==.Kailis:BAAANQAECgUIDQAAAA==.Kaisa:BAAANQAECgUICAAAAA==.Karst:BAAANQADCggIIQAAAA==.Kayzon:BAACNQAFFIEWAAIOAAcKaxfYAABbAgAOAAcKaxfYAABbAgA1AAQKgR4AAg4ACQq6JMEKAGYDAA4ACQq6JMEKAGYDAAAA.',
Ki='Kirayn:BAAANQABCgIIAgAAAA==.',
Kl='Klavine:BAABNQAECoEeAAIPAAkKcxfRHABYAgAPAAkKcxfRHABYAgAAAA==.',
Ko='Korben:BAAANQAECgYJDgAAAA==.',
Kr='Kragorn:BAAANQAECgUIDAAAAA==.Kronn:BAAANQADCgYIBgAAAA==.',
Ku='Kublakhan:BAAANQAECgUICQAAAA==.',
Ky='Kylaania:BAAANQADCgEJAQAAAA==.Kynleria:BAAANQADCgMJAwAAAA==.',
['Kõ']='Kõrin:BAAANQADCggJDwAAAA==.',
La='Lakhi:BAAANQAECgQICQAAAA==.Lanerath:BAAANQAECgEIAQAAAA==.Lapras:BAECNQAFFIEPAAIQAAUKcSbVAABDAgAQAAUKcSbVAABDAgA1AAQKgR8AAhAACQq4JjAAAPsDABAACQq4JjAAAPsDAAAA.Laureli:BAAANQADCggIHwAAAA==.',
Le='Leeta:BAAANQADCggIIgABNQAECgQICQABAAAAAA==.Lemooski:BAAANQAECgIIAgABNQAFFAQICAARALYMAA==.Leorra:BAAANQAECgUICQAAAA==.Letholdus:BAAANQAECgUICQAAAA==.',
Li='Lightningg:BAAANQAECgQICAAAAA==.Linara:BAAANQAECgEIAQABNQAECgYIEgABAAAAAA==.',
Lo='Loraemar:BAAANQADCggIDAAAAA==.Losoz:BAAANQADCgcIDQAAAA==.',
Lu='Lucariel:BAAANQAECgQIBwAAAA==.Lusilsandrus:BAAANQAECgQJBgAAAA==.',
Ma='Maddlib:BAABNQAECoEjAAIGAAkKdRxXFQDUAgAGAAkKdRxXFQDUAgAAAA==.Maegwin:BAABNQAECoEbAAICAAcKkRHQZgCBAQACAAcKkRHQZgCBAQAAAA==.Magicpie:BAAANQADCgQIBAAAAA==.Maglani:BAAANQADCggIDgAAAA==.Mahoutsukai:BAAANQADCgcIBwAAAA==.Maizie:BAAANQABCgQIBgAAAA==.Mania:BAABNQAECoEhAAMPAAkKQB9rEADSAgAPAAgKRyBrEADSAgASAAYKDwzoZgAMAQAAAA==.Matcauthon:BAAANQAECgQJBQAAAA==.Matti:BAAANQADCggIIQAAAA==.Maul:BAAANQADCgEJAgAAAA==.',
Me='Mellaise:BAAANQABCgIIAgAAAA==.',
Mi='Miami:BAAANQAECgUIBQABNQAFFAYIFAAQAEYZAA==.Mildrik:BAAANQAECgUIDQAAAA==.Mindle:BAAANQADCgUIBQAAAA==.Miracledk:BAAANQAECgQIBAAAAA==.Mirkdrak:BAAANQAECgEIAQABNQAECgYIEAABAAAAAA==.Mishach:BAAANQADCggIDwABNQAECgQIBAABAAAAAA==.Misheard:BAAANQAECgYIEgAAAA==.Misjudged:BAACNQAFFIEHAAMTAAMKiw6dBADYAAATAAMKiw6dBADYAAAQAAEKCAHUDQAqAAA1AAQKgSMAAxMACQr1GEsFAE4CABMACArAGUsFAE4CABAABgq9EiobAFoBAAAA.Missmarsha:BAAANQAECgQICAAAAA==.Mit:BAAANQAECgYIDgAAAA==.Mizzen:BAAANQAECgYIEAABNQAECgkJJwADACsaAA==.',
Mo='Moegis:BAAANQADCgEIAQAAAA==.Mohtavius:BAAANQAECgQIBAAAAA==.Mommydearest:BAAANQAECgYIEQAAAA==.Mongrell:BAAANQAECgQIBAAAAA==.Moonkissed:BAAANQADCgcIFwAAAA==.Motz:BAAANQAECgEIAgAAAA==.',
Mu='Munkìe:BAAANQADCgEIAQABNQAECgQICAABAAAAAA==.Muura:BAABNQAECoEWAAMSAAgKNAo5UwBeAQASAAcKZgs5UwBeAQAPAAQKWgI6bAB3AAAAAA==.',
My='Mylitlepwny:BAAANQADCgUJCQAAAA==.',
['Må']='Mågè:BAAANQADCggICAAAAA==.',
['Mè']='Mèièr:BAAANQADCgUIBQAAAA==.',
Na='Nabsta:BAAANQADCgQJBQAAAA==.Namini:BAAANQADCgMJAwABNQAECgQICAABAAAAAA==.Narcissist:BAAANQABCggIDAAAAA==.Nathyrra:BAAANQAECgYIBgABNQAECgUIDgABAAAAAA==.',
Ne='Nekorii:BAAANQAECgQIBAAAAA==.',
Ni='Niteroot:BAAANQAECgMIAwAAAA==.',
Oe='Oekabe:BAAANQADCgQIBAAAAA==.',
Ot='Otwin:BAAANQAECgIIAwAAAA==.',
Pa='Pahuum:BAAANQADCggIDAAAAA==.Paimon:BAAANQAECgQIBAABNQAFFAYIFAAEALMBAA==.Palleigh:BAAANQADCggIEgAAAA==.Pamaro:BAAANQAECgUJBQAAAA==.',
Pe='Pepperjack:BAAANQADCggIIQABNQAECgMIAwABAAAAAA==.Peril:BAAANQABCgYICgAAAA==.Persimmon:BAAANQAECgYIEgAAAA==.',
Po='Poondor:BAAANQAECgYICQAAAA==.',
Pr='Predaturd:BAAANQADCgcIDAAAAA==.Prettydruid:BAAANQAECgUJCgAAAA==.',
Qi='Qindere:BAAANQADCgUIBQAAAA==.',
Ra='Raeinthe:BAABNQAECoEcAAIOAAgKeBi4PABtAgAOAAgKeBi4PABtAgAAAA==.Rakshaman:BAAANQAECgQICQAAAA==.',
Re='Rebarahl:BAAANQADCgEIAQAAAA==.Resiaus:BAABNQAECoElAAIUAAgKwBGoGAD5AQAUAAgKwBGoGAD5AQAAAA==.',
Ri='Rivalina:BAAANQADCgMIAwAAAA==.',
Ru='Run:BAABNQAECoEVAAMMAAkK1gvfYwCOAQAMAAcKZA7fYwCOAQADAAcKYgN0OgD+AAABNQAFFAYIFAAEALMBAA==.',
Ry='Ry:BAAANQAECgQIDQAAAA==.',
Sa='Sachtat:BAAANQAECgUICQAAAA==.Saintfoxtrot:BAEANQADCgIIAgAAAA==.Salandre:BAAANQABCggIEwAAAA==.Sangairee:BAAANQABCgYIBgAAAA==.Saraya:BAAANQAECgUICAAAAA==.',
Sc='Scarletheart:BAAANQADCgEIAQAAAA==.',
Se='Setsena:BAAANQAECgYIEgAAAA==.',
Sh='Shamanta:BAAANQADCgEIAQAAAA==.Shatterstr:BAAANQADCggICAAAAA==.Shibaryotaro:BAAANQADCgIIAgAAAA==.Shieldunit:BAAANQAECgEIAQAAAA==.Shinstabber:BAAANQAECgYIEgAAAA==.Shivantice:BAAANQAECgQIBAAAAA==.Shruggie:BAAANQAECgEIAgAAAA==.Shìnobu:BAAANQAECgUICQAAAA==.',
Si='Siphondark:BAAANQAECgYIDwAAAA==.Siphondrood:BAAANQADCgYIBgAAAA==.',
Sm='Smidgen:BAAANQAECgQIBAAAAA==.Smolnad:BAAANQADCggJGgAAAA==.',
So='Solarís:BAAANQAECgEIAQAAAA==.Solvaii:BAAANQADCgQIBAAAAA==.',
Sp='Spicee:BAAANQABCgYICQAAAA==.Spudsy:BAAANQADCgUIBQAAAA==.',
St='Stinkerbella:BAAANQADCgEIAQAAAA==.Stratacaster:BAAANQADCggICAAAAA==.Stungyou:BAAANQADCgIJAgAAAA==.',
Sy='Syela:BAAANQADCgUIBQABNQAECgYIBgABAAAAAA==.Synbiot:BAEANQAECggJCAABNQAECggIFgAJAHQHAA==.Synfyl:BAEANQAECggICAABNQAECggIFgAJAHQHAA==.Synpathi:BAEANQAECggIAgABNQAECggIFgAJAHQHAA==.Synsyn:BAEBNQAECoEWAAQJAAgKdAdKRgCYAAAIAAUKcQUz1gC2AAAJAAMKgwdKRgCYAAAVAAIKFwhBGgBwAAAAAA==.Syyner:BAAANQADCgMIAwAAAA==.',
Ta='Tach:BAAANQAECgEIAQAAAA==.Tails:BAAANQABCgQIBAAAAA==.Tamplarmage:BAAANQADCgUICAAAAA==.Tatsü:BAAANQAECgIIAwAAAA==.Taytemswift:BAAANQADCgIIAgABNQAECgMIBAABAAAAAA==.Taílorswift:BAAANQAECgMIBAAAAA==.',
Te='Telise:BAAANQADCgMIAwAAAA==.Temna:BAAANQAECgQICAAAAA==.Terepal:BAAANQADCggICgAAAA==.',
Th='Theel:BAAANQADCgYJCwAAAA==.Theruss:BAAANQADCgEIAgAAAA==.Thornagan:BAAANQADCgYJBgABNQADCgYIBgABAAAAAA==.Thredora:BAAANQADCgYIBgAAAA==.Thundie:BAAANQADCgIIAgAAAA==.',
Ti='Tinbasher:BAAANQADCggIEQAAAA==.',
To='Toast:BAAANQADCggICAAAAA==.Toserve:BAAANQABCgIIAgAAAA==.',
Tr='Tragoul:BAAANQABCgMIAwAAAA==.Treebilly:BAAANQADCgYIBgAAAA==.Tricky:BAAANQADCgYICQAAAA==.',
Tw='Tweetêr:BAAANQABCgQJBQAAAA==.',
Ut='Uttrsdeek:BAABNQAECoEVAAMSAAkKehwPLQAmAgASAAgK9BkPLQAmAgAPAAYKIhr8MgCnAQAAAA==.',
Va='Valfurian:BAAANQADCggICAABNQADCggIIgABAAAAAA==.Valkky:BAAANQAECgQIBAAAAA==.Valky:BAAANQAECgIJAgABNQAECgQIBAABAAAAAA==.Vallysong:BAAANQADCgYIDgABNQADCggIFAABAAAAAA==.Vandeta:BAAANQAECgQIBgAAAA==.Vasoline:BAAANQAECgcIAQABNQAECggIAQABAAAAAA==.Vatz:BAAANQADCgYIBgAAAA==.',
Ve='Velenn:BAAANQADCggIFAAAAA==.Venatar:BAAANQAECgQIBwAAAA==.Vessna:BAAANQAECgEIAQABNQAECgYIEAABAAAAAA==.Veti:BAAANQAECgUICAAAAA==.',
Vi='Vivîán:BAAANQAECgEIAQAAAA==.',
Vo='Vodic:BAABNQAECoEaAAMHAAgKOQ7dFwD7AQAHAAgKOQ7dFwD7AQAWAAEK5gmWcABCAAAAAA==.Voras:BAAANQAECgYIEQAAAA==.Vorttex:BAAANQADCgYICgAAAA==.',
Wa='Warbilly:BAAANQADCggICQAAAA==.Wasure:BAAANQADCggIGgAAAA==.',
Wo='Worthy:BAAANQADCgQIBAAAAA==.',
Xe='Xeleik:BAAANQAECgUIDQAAAA==.',
Xu='Xunay:BAAANQABCggIDAAAAA==.',
Xy='Xylar:BAAANQAECgIIAgAAAA==.',
Yo='Yoshino:BAAANQAECgMIBAABNQADCgUIBgABAAAAAA==.',
Yu='Yukilumi:BAAANQADCgEIAQAAAA==.',
Ze='Zeynah:BAAANQADCgcICgAAAA==.',
Zi='Ziroquois:BAAANQABCgYIBwAAAA==.',
Zo='Zoedan:BAAANQADCgMIBQAAAA==.Zophier:BAAANQADCgYIBgAAAA==.Zouk:BAAANQADCgcJAgAAAA==.Zoéy:BAAANQAECgUIBQAAAA==.',
Zu='Zube:BAAANQAECgYIEwAAAA==.',
Zy='Zyrren:BAAANQADCgYJBgAAAA==.',
['Âu']='Âuranna:BAAANQADCgQIBAAAAA==.',
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
